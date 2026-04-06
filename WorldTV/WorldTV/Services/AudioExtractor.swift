import Foundation
import AVFoundation
import AudioToolbox

// MARK: - AudioExtractor

/// Extracts audio from HLS streams by downloading .ts segments,
/// demuxing MPEG-TS to get AAC frames, then decoding to 16kHz mono Float32 PCM.
class AudioExtractor: @unchecked Sendable {

    enum ExtractorError: LocalizedError {
        case invalidManifest
        case noAudioPID
        case decodeFailed(String)

        var errorDescription: String? {
            switch self {
            case .invalidManifest: return "Invalid HLS manifest"
            case .noAudioPID: return "No audio PID in TS"
            case .decodeFailed(let r): return r
            }
        }
    }

    private(set) var isRunning = false
    var isExtractorRunning: Bool { isRunning }
    private(set) var lastError: String = ""

    private var onAudioBuffer: (([Float]) -> Void)?
    private var currentTask: Task<Void, Never>?
    private var processedSegments: Set<String> = []
    private let pollInterval: TimeInterval = 4.0

    func setAudioCallback(_ callback: @escaping ([Float]) -> Void) {
        onAudioBuffer = callback
    }

    func start(url: URL) {
        stop()
        isRunning = true
        processedSegments.removeAll()
        lastError = "Starting..."

        currentTask = Task { [weak self] in
            guard let self else { return }
            await self.extractionLoop(manifestURL: url)
        }
    }

    func stop() {
        isRunning = false
        currentTask?.cancel()
        currentTask = nil
    }

    // MARK: - Extraction Loop

    private func extractionLoop(manifestURL: URL) async {
        print("[AudioExtractor] extractionLoop started: \(manifestURL)")
        while isRunning, !Task.isCancelled {
            do {
                let segmentURLs = try await resolveSegmentURLs(from: manifestURL)
                lastError = "Segs:\(segmentURLs.count) done:\(processedSegments.count)"
                print("[AudioExtractor] \(lastError)")

                if processedSegments.isEmpty, let first = segmentURLs.first {
                    print("[AudioExtractor] First segment URL: \(first.absoluteString)")
                }

                for segmentURL in segmentURLs {
                    guard isRunning, !Task.isCancelled else { break }

                    let key = segmentURL.absoluteString
                    if processedSegments.contains(key) { continue }
                    processedSegments.insert(key)

                    do {
                        let samples = try await extractAudioFromSegment(segmentURL)
                        if !samples.isEmpty {
                            lastError = "OK:\(samples.count) samples"
                            print("[AudioExtractor] OK: \(samples.count) PCM samples from segment")
                            onAudioBuffer?(samples)
                        }
                    } catch {
                        lastError = "Seg: \(error.localizedDescription)"
                        print("[AudioExtractor] Seg error: \(error.localizedDescription) URL: \(segmentURL.absoluteString)")
                    }
                }
            } catch {
                lastError = "M: \(error.localizedDescription)"
            }

            try? await Task.sleep(nanoseconds: UInt64(pollInterval * 1_000_000_000))
        }
    }

    // MARK: - Segment Audio Extraction

    private func extractAudioFromSegment(_ url: URL) async throws -> [Float] {
        let (data, response) = try await URLSession.shared.data(from: url)
        let http = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard http == 200, data.count > 188 else {
            throw ExtractorError.decodeFailed("HTTP\(http) \(data.count)B")
        }

        // 1. Demux MPEG-TS to extract AAC ADTS frames
        let adtsFrames: [Data]
        do {
            adtsFrames = try demuxAudio(from: data)
        } catch {
            throw ExtractorError.decodeFailed("Demux: \(error.localizedDescription)")
        }
        guard !adtsFrames.isEmpty else {
            throw ExtractorError.noAudioPID
        }

        // 2. Concatenate all ADTS frames
        let adtsData = adtsFrames.reduce(Data()) { $0 + $1 }
        NSLog("[AudioExtractor] Got %d ADTS frames, %d bytes total", adtsFrames.count, adtsData.count)

        // 3. Decode AAC ADTS to 16kHz mono Float32 PCM
        let pcmSamples: [Float]
        do {
            pcmSamples = try decodeAACToPCM(adtsData: adtsData)
        } catch {
            throw ExtractorError.decodeFailed("AAC: \(error.localizedDescription)")
        }
        return pcmSamples
    }

    // MARK: - MPEG-TS Demuxer

    /// Safe byte access helper
    private func byte(_ data: Data, _ index: Int) -> UInt8 {
        guard index >= 0, index < data.count else { return 0 }
        return data[index]
    }

    /// Parse MPEG-TS packets and extract AAC ADTS frames from audio PES packets.
    private func demuxAudio(from tsData: Data) throws -> [Data] {
        let packetSize = 188
        let syncByte: UInt8 = 0x47
        var audioPID: UInt16? = nil
        var pesBuffer = Data()
        var adtsFrames: [Data] = []
        let totalSize = tsData.count

        guard totalSize >= packetSize else {
            throw ExtractorError.decodeFailed("TS data too small: \(totalSize)")
        }

        // First pass: find audio PID from PAT -> PMT
        var pmtPID: UInt16? = nil
        var offset = 0

        // Find sync byte
        while offset < totalSize - packetSize {
            if tsData[offset] == syncByte { break }
            offset += 1
        }

        // Scan for PAT and PMT
        var scanOffset = offset
        while scanOffset + packetSize <= totalSize {
            guard byte(tsData, scanOffset) == syncByte else {
                scanOffset += 1
                continue
            }

            let b1 = byte(tsData, scanOffset + 1)
            let b2 = byte(tsData, scanOffset + 2)
            let b3 = byte(tsData, scanOffset + 3)
            let pid = (UInt16(b1 & 0x1F) << 8) | UInt16(b2)
            let hasPayload = (b3 & 0x10) != 0
            let hasAdaptation = (b3 & 0x20) != 0
            let payloadUnitStart = (b1 & 0x40) != 0

            var payloadStart = scanOffset + 4
            if hasAdaptation, payloadStart < scanOffset + packetSize {
                let adaptLen = Int(byte(tsData, payloadStart))
                payloadStart += 1 + adaptLen
            }

            guard hasPayload, payloadStart < scanOffset + packetSize else {
                scanOffset += packetSize
                continue
            }

            let pktEnd = scanOffset + packetSize

            // PAT (PID 0)
            if pid == 0, payloadUnitStart, payloadStart + 1 < pktEnd {
                let pointerField = Int(byte(tsData, payloadStart))
                var p = payloadStart + 1 + pointerField
                if p + 8 < pktEnd {
                    let sectionLength = Int(byte(tsData, p + 1) & 0x0F) << 8 | Int(byte(tsData, p + 2))
                    p += 8
                    let endOfSection = min(payloadStart + 1 + pointerField + 3 + sectionLength, pktEnd)
                    while p + 4 <= max(0, endOfSection - 4), p + 3 < totalSize {
                        let programNum = (UInt16(byte(tsData, p)) << 8) | UInt16(byte(tsData, p + 1))
                        let programPID = (UInt16(byte(tsData, p + 2) & 0x1F) << 8) | UInt16(byte(tsData, p + 3))
                        if programNum != 0 {
                            pmtPID = programPID
                            break
                        }
                        p += 4
                    }
                }
            }

            // PMT
            if let pmt = pmtPID, pid == pmt, payloadUnitStart, audioPID == nil, payloadStart + 1 < pktEnd {
                let pointerField = Int(byte(tsData, payloadStart))
                var p = payloadStart + 1 + pointerField
                if p + 12 < pktEnd {
                    let sectionLength = Int(byte(tsData, p + 1) & 0x0F) << 8 | Int(byte(tsData, p + 2))
                    let programInfoLength = Int(byte(tsData, p + 10) & 0x0F) << 8 | Int(byte(tsData, p + 11))
                    p += 12 + programInfoLength
                    let endOfSection = min(payloadStart + 1 + pointerField + 3 + sectionLength, pktEnd)
                    while p + 5 <= max(0, endOfSection - 4), p + 4 < totalSize {
                        let streamType = byte(tsData, p)
                        let elementaryPID = (UInt16(byte(tsData, p + 1) & 0x1F) << 8) | UInt16(byte(tsData, p + 2))
                        let esInfoLength = Int(byte(tsData, p + 3) & 0x0F) << 8 | Int(byte(tsData, p + 4))

                        // AAC: 0x0F, AAC-LATM: 0x11, MP3: 0x03/0x04
                        if streamType == 0x0F || streamType == 0x11 || streamType == 0x03 || streamType == 0x04 {
                            audioPID = elementaryPID
                            NSLog("[AudioExtractor] Found audio PID: %d, type: 0x%02X", elementaryPID, streamType)
                            break
                        }
                        p += 5 + esInfoLength
                    }
                }
            }

            if audioPID != nil { break }
            scanOffset += packetSize
        }

        guard let aPID = audioPID else {
            throw ExtractorError.noAudioPID
        }

        // Second pass: extract audio PES data
        var readOffset = offset
        while readOffset + packetSize <= totalSize {
            guard byte(tsData, readOffset) == syncByte else {
                readOffset += 1
                continue
            }

            let b1 = byte(tsData, readOffset + 1)
            let b3 = byte(tsData, readOffset + 3)
            let pid = (UInt16(b1 & 0x1F) << 8) | UInt16(byte(tsData, readOffset + 2))
            let hasPayload = (b3 & 0x10) != 0
            let hasAdaptation = (b3 & 0x20) != 0
            let payloadUnitStart = (b1 & 0x40) != 0

            if pid == aPID, hasPayload {
                var payloadStart = readOffset + 4
                if hasAdaptation, payloadStart < readOffset + packetSize {
                    let adaptLen = Int(byte(tsData, payloadStart))
                    payloadStart += 1 + adaptLen
                }

                if payloadUnitStart, !pesBuffer.isEmpty {
                    let frames = extractADTSFrames(from: pesBuffer)
                    adtsFrames.append(contentsOf: frames)
                    pesBuffer.removeAll()
                }

                let payloadEnd = min(readOffset + packetSize, totalSize)
                if payloadStart < payloadEnd {
                    pesBuffer.append(tsData[payloadStart..<payloadEnd])
                }
            }

            readOffset += packetSize
        }

        // Flush remaining
        if !pesBuffer.isEmpty {
            let frames = extractADTSFrames(from: pesBuffer)
            adtsFrames.append(contentsOf: frames)
        }

        return adtsFrames
    }

    /// Extract ADTS frames from a PES packet payload.
    private func extractADTSFrames(from pesData: Data) -> [Data] {
        var frames: [Data] = []
        var offset = 0

        // Skip PES header: find ADTS sync word (0xFFF)
        // PES header: 00 00 01 stream_id ...
        if pesData.count > 9,
           pesData[0] == 0x00, pesData[1] == 0x00, pesData[2] == 0x01 {
            let headerDataLength = Int(pesData[8])
            offset = 9 + headerDataLength
        }

        // Find and extract ADTS frames (sync: 0xFFF)
        while offset + 7 <= pesData.count {
            // Look for ADTS sync word
            if pesData[offset] == 0xFF, (pesData[offset + 1] & 0xF0) == 0xF0 {
                // Parse ADTS header to get frame length
                let frameLength = (Int(pesData[offset + 3] & 0x03) << 11) |
                                  (Int(pesData[offset + 4]) << 3) |
                                  (Int(pesData[offset + 5]) >> 5)

                if frameLength > 0, offset + frameLength <= pesData.count {
                    frames.append(pesData[offset..<(offset + frameLength)])
                    offset += frameLength
                } else {
                    break
                }
            } else {
                offset += 1
            }
        }

        return frames
    }

    // MARK: - AAC Decode

    /// Decode AAC ADTS data to 16kHz mono Float32 PCM using AVAudioFile.
    private func decodeAACToPCM(adtsData: Data) throws -> [Float] {
        let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".aac")
        try adtsData.write(to: tempFile)
        defer { try? FileManager.default.removeItem(at: tempFile) }

        // Open with AVAudioFile (safer than ExtAudioFile)
        let audioFile: AVAudioFile
        do {
            audioFile = try AVAudioFile(forReading: tempFile)
        } catch {
            throw ExtractorError.decodeFailed("AVAudioFile: \(error.localizedDescription)")
        }

        let srcFormat = audioFile.processingFormat
        let frameCount = AVAudioFrameCount(audioFile.length)
        NSLog("[AudioExtractor] AAC file: rate=%.0f ch=%d frames=%d",
              srcFormat.sampleRate, srcFormat.channelCount, frameCount)

        guard frameCount > 0 else {
            throw ExtractorError.decodeFailed("Empty AAC file")
        }

        // Read all frames at source format
        guard let srcBuffer = AVAudioPCMBuffer(pcmFormat: srcFormat, frameCapacity: frameCount) else {
            throw ExtractorError.decodeFailed("Buffer alloc failed")
        }

        do {
            try audioFile.read(into: srcBuffer)
        } catch {
            throw ExtractorError.decodeFailed("Read: \(error.localizedDescription)")
        }

        // Convert to 16kHz mono Float32
        guard let dstFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                            sampleRate: 16000.0,
                                            channels: 1,
                                            interleaved: false) else {
            throw ExtractorError.decodeFailed("Dst format failed")
        }

        guard let converter = AVAudioConverter(from: srcFormat, to: dstFormat) else {
            throw ExtractorError.decodeFailed("Converter failed")
        }

        // Calculate output frame count
        let ratio = 16000.0 / srcFormat.sampleRate
        let outputFrames = AVAudioFrameCount(Double(srcBuffer.frameLength) * ratio)
        guard let dstBuffer = AVAudioPCMBuffer(pcmFormat: dstFormat, frameCapacity: outputFrames + 1024) else {
            throw ExtractorError.decodeFailed("Dst buffer failed")
        }

        var error: NSError?
        var inputConsumed = false
        converter.convert(to: dstBuffer, error: &error) { _, outStatus in
            if inputConsumed {
                outStatus.pointee = .endOfStream
                return nil
            }
            inputConsumed = true
            outStatus.pointee = .haveData
            return srcBuffer
        }

        if let error = error {
            throw ExtractorError.decodeFailed("Convert: \(error.localizedDescription)")
        }

        // Extract Float32 samples
        guard let channelData = dstBuffer.floatChannelData else {
            throw ExtractorError.decodeFailed("No channel data")
        }

        let count = Int(dstBuffer.frameLength)
        let samples = Array(UnsafeBufferPointer(start: channelData[0], count: count))
        NSLog("[AudioExtractor] Decoded %d PCM samples (16kHz mono)", count)
        return samples
    }

    // MARK: - HLS Manifest Parsing

    private func resolveSegmentURLs(from url: URL) async throws -> [URL] {
        let lines = try await fetchManifestLines(url: url)
        if lines.contains(where: { $0.hasPrefix("#EXT-X-STREAM-INF:") }) {
            guard let variantURL = firstVariantURL(lines: lines, baseURL: url) else {
                throw ExtractorError.invalidManifest
            }
            print("[AudioExtractor] Variant playlist: \(variantURL)")
            return try await parseMediaPlaylist(url: variantURL)
        }
        return parseSegmentURLs(lines: lines, baseURL: url)
    }

    private func parseMediaPlaylist(url: URL) async throws -> [URL] {
        let lines = try await fetchManifestLines(url: url)
        return parseSegmentURLs(lines: lines, baseURL: url)
    }

    private func fetchManifestLines(url: URL) async throws -> [String] {
        let (data, _) = try await URLSession.shared.data(from: url)
        guard let content = String(data: data, encoding: .utf8) else {
            throw ExtractorError.invalidManifest
        }
        return content.components(separatedBy: .newlines)
    }

    private func firstVariantURL(lines: [String], baseURL: URL) -> URL? {
        var found = false
        for line in lines {
            let t = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if t.hasPrefix("#EXT-X-STREAM-INF:") { found = true; continue }
            if found, !t.isEmpty, !t.hasPrefix("#") { return resolveURL(t, against: baseURL) }
        }
        return nil
    }

    private func parseSegmentURLs(lines: [String], baseURL: URL) -> [URL] {
        lines.compactMap { line in
            let t = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !t.isEmpty, !t.hasPrefix("#") else { return nil }
            return resolveURL(t, against: baseURL)
        }
    }

    private func resolveURL(_ string: String, against baseURL: URL) -> URL? {
        if string.hasPrefix("http://") || string.hasPrefix("https://") {
            return URL(string: string)
        }
        return baseURL.deletingLastPathComponent().appendingPathComponent(string)
    }
}
