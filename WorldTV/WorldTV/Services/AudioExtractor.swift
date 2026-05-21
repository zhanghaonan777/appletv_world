import Foundation
import AVFoundation
import MediaToolbox

// MARK: - AudioExtractor

/// Taps the decoded audio of an AVPlayer's current item via MTAudioProcessingTap.
/// The tap receives the exact PCM the player is rendering, so subtitles stay in
/// sync with the picture and no extra network download is needed.
/// Audio is mixed to mono and resampled to 16kHz Float32 for Whisper.
final class AudioExtractor: @unchecked Sendable {

    static let targetSampleRate: Double = 16000

    private(set) var lastError: String = ""

    private var onAudioBuffer: (([Float]) -> Void)?
    private var tap: MTAudioProcessingTap?
    private weak var playerItem: AVPlayerItem?
    private var attachTask: Task<Void, Never>?
    private var simTask: Task<Void, Never>?

    // Set by the prepare callback once the player reveals its audio format.
    fileprivate var sourceSampleRate: Double = 48000

    // Accumulates resampled mono audio so we emit ~0.5s chunks instead of
    // firing the callback on every tiny tap buffer.
    private let lock = NSLock()
    private var pending: [Float] = []
    private let flushThreshold = 8000  // 0.5s at 16kHz

    func setAudioCallback(_ callback: @escaping ([Float]) -> Void) {
        onAudioBuffer = callback
    }

    func start(player: AVPlayer) {
        stop()
        #if targetEnvironment(simulator)
        // MTAudioProcessingTap does not deliver audio in the tvOS Simulator,
        // so stream a bundled speech clip instead — lets the full pipeline
        // (stream -> server -> subtitle) be demoed without a real device.
        startSimulatedAudio()
        #else
        guard let item = player.currentItem else {
            lastError = "无播放项"
            return
        }
        playerItem = item
        attachTask = Task { [weak self] in
            guard let self else { return }
            await self.attachTap(to: item)
        }
        #endif
    }

    func stop() {
        attachTask?.cancel()
        attachTask = nil
        simTask?.cancel()
        simTask = nil
        playerItem?.audioMix = nil
        playerItem = nil
        tap = nil
        lock.lock()
        pending.removeAll(keepingCapacity: false)
        lock.unlock()
    }

    // MARK: - Simulator Audio Source

    private func startSimulatedAudio() {
        guard let samples = Self.loadSimulatedSpeech() else {
            lastError = "找不到 sim_speech.wav"
            return
        }
        lastError = "模拟音频流(模拟器)"
        simTask = Task { [weak self] in
            let chunk = 8000  // 0.5s at 16kHz
            var index = 0
            while !Task.isCancelled {
                let end = min(index + chunk, samples.count)
                self?.onAudioBuffer?(Array(samples[index..<end]))
                index = end >= samples.count ? 0 : end   // loop the clip
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
        }
    }

    private static func loadSimulatedSpeech() -> [Float]? {
        guard let url = Bundle.main.url(forResource: "sim_speech", withExtension: "wav"),
              let file = try? AVAudioFile(forReading: url) else { return nil }
        let format = file.processingFormat
        let frameCount = AVAudioFrameCount(file.length)
        guard frameCount > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount),
              (try? file.read(into: buffer)) != nil,
              let channelData = buffer.floatChannelData else { return nil }
        return Array(UnsafeBufferPointer(start: channelData[0], count: Int(buffer.frameLength)))
    }

    // MARK: - Tap Attachment

    private func attachTap(to item: AVPlayerItem) async {
        // HLS audio tracks may not be available immediately — retry briefly.
        var audioTrack: AVAssetTrack?
        for attempt in 0..<5 {
            if Task.isCancelled { return }
            do {
                let tracks = try await item.asset.loadTracks(withMediaType: .audio)
                if let track = tracks.first {
                    audioTrack = track
                    break
                }
            } catch {
                lastError = "轨道加载失败: \(error.localizedDescription)"
            }
            if attempt < 4 {
                try? await Task.sleep(nanoseconds: 600_000_000)
            }
        }

        guard let audioTrack else {
            lastError = "无法获取音频轨道(此流不支持 AI 字幕)"
            return
        }
        guard !Task.isCancelled else { return }
        await MainActor.run { self.installTap(on: item, track: audioTrack) }
    }

    private func installTap(on item: AVPlayerItem, track: AVAssetTrack) {
        var callbacks = MTAudioProcessingTapCallbacks(
            version: kMTAudioProcessingTapCallbacksVersion_0,
            clientInfo: Unmanaged.passUnretained(self).toOpaque(),
            init: tapInit,
            finalize: tapFinalize,
            prepare: tapPrepare,
            unprepare: tapUnprepare,
            process: tapProcess
        )

        var tapRef: MTAudioProcessingTap?
        let status = MTAudioProcessingTapCreate(
            kCFAllocatorDefault, &callbacks,
            kMTAudioProcessingTapCreationFlag_PostEffects, &tapRef
        )
        guard status == noErr, let tapRef else {
            lastError = "Tap 创建失败 (\(status))"
            return
        }
        tap = tapRef

        let params = AVMutableAudioMixInputParameters(track: track)
        params.audioTapProcessor = tapRef
        let mix = AVMutableAudioMix()
        mix.inputParameters = [params]
        item.audioMix = mix
        lastError = "Tap 已安装"
    }

    // MARK: - Audio Processing (called from the tap's realtime thread)

    fileprivate func process(bufferList: UnsafeMutablePointer<AudioBufferList>, frames: Int) {
        guard frames > 0 else { return }
        let abl = UnsafeMutableAudioBufferListPointer(bufferList)
        guard abl.count > 0 else { return }

        // Mix every channel (interleaved or planar) down to mono.
        var mono = [Float](repeating: 0, count: frames)
        var channelCount = 0
        for buffer in abl {
            guard let data = buffer.mData else { continue }
            let ch = max(1, Int(buffer.mNumberChannels))
            let ptr = data.assumingMemoryBound(to: Float.self)
            let available = Int(buffer.mDataByteSize) / MemoryLayout<Float>.size / ch
            let n = min(frames, available)
            for c in 0..<ch {
                for i in 0..<n {
                    mono[i] += ptr[i * ch + c]
                }
                channelCount += 1
            }
        }
        if channelCount > 1 {
            let scale = 1.0 / Float(channelCount)
            for i in 0..<frames { mono[i] *= scale }
        }

        let resampled = Self.resampleLinear(mono, from: sourceSampleRate, to: Self.targetSampleRate)
        guard !resampled.isEmpty else { return }

        lock.lock()
        pending.append(contentsOf: resampled)
        let ready = pending.count >= flushThreshold
        let chunk = ready ? pending : []
        if ready { pending.removeAll(keepingCapacity: true) }
        lock.unlock()

        if ready { onAudioBuffer?(chunk) }
    }

    private static func resampleLinear(_ input: [Float], from srcRate: Double, to dstRate: Double) -> [Float] {
        guard srcRate > 0, dstRate > 0, !input.isEmpty else { return [] }
        if abs(srcRate - dstRate) < 1 { return input }

        let ratio = srcRate / dstRate
        let outCount = Int(Double(input.count) / ratio)
        guard outCount > 0 else { return [] }

        var output = [Float](repeating: 0, count: outCount)
        for i in 0..<outCount {
            let srcPos = Double(i) * ratio
            let idx = Int(srcPos)
            let frac = Float(srcPos - Double(idx))
            let a = input[idx]
            let b = idx + 1 < input.count ? input[idx + 1] : a
            output[i] = a + (b - a) * frac
        }
        return output
    }
}

// MARK: - MTAudioProcessingTap C Callbacks

private func tapInit(tap: MTAudioProcessingTap,
                     clientInfo: UnsafeMutableRawPointer?,
                     tapStorageOut: UnsafeMutablePointer<UnsafeMutableRawPointer?>) {
    tapStorageOut.pointee = clientInfo
}

private func tapFinalize(tap: MTAudioProcessingTap) {}

private func tapPrepare(tap: MTAudioProcessingTap,
                        maxFrames: CMItemCount,
                        processingFormat: UnsafePointer<AudioStreamBasicDescription>) {
    let extractor = Unmanaged<AudioExtractor>
        .fromOpaque(MTAudioProcessingTapGetStorage(tap)).takeUnretainedValue()
    extractor.sourceSampleRate = processingFormat.pointee.mSampleRate
}

private func tapUnprepare(tap: MTAudioProcessingTap) {}

private func tapProcess(tap: MTAudioProcessingTap,
                        numberFrames: CMItemCount,
                        flags: MTAudioProcessingTapFlags,
                        bufferListInOut: UnsafeMutablePointer<AudioBufferList>,
                        numberFramesOut: UnsafeMutablePointer<CMItemCount>,
                        flagsOut: UnsafeMutablePointer<MTAudioProcessingTapFlags>) {
    let status = MTAudioProcessingTapGetSourceAudio(
        tap, numberFrames, bufferListInOut, flagsOut, nil, numberFramesOut
    )
    guard status == noErr else { return }

    let extractor = Unmanaged<AudioExtractor>
        .fromOpaque(MTAudioProcessingTapGetStorage(tap)).takeUnretainedValue()
    extractor.process(bufferList: bufferListInOut, frames: Int(numberFramesOut.pointee))
}
