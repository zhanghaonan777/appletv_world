import Foundation
import SwiftUI
import AVFoundation

// MARK: - SubtitleDisplayMode

enum SubtitleDisplayMode: String, CaseIterable {
    case off = "关闭字幕"
    case originalOnly = "仅原文"
    case translationOnly = "仅翻译"
    case both = "原文+翻译"
}

// MARK: - SubtitleEngine

/// Coordinates the audio extraction -> speech recognition -> translation -> subtitle display pipeline.
@MainActor
class SubtitleEngine: ObservableObject {

    // MARK: - Published State

    @Published var currentOriginalText: String = ""
    @Published var currentTranslatedText: String = ""
    @Published var isActive: Bool = false
    @Published var sourceLanguage: String = "en"
    @Published var targetLanguage: String = "zh"
    @Published var pipelineStatus: String = "等待启动"
    @Published var displayMode: SubtitleDisplayMode = .both

    // MARK: - Private

    private var audioExtractor: AudioExtractor?
    private var processingTask: Task<Void, Never>?
    private var whisperService: WhisperService?
    private var translationService: TranslationService?

    private let windowSize: Int = 48000  // 3 seconds sliding window at 16kHz
    private var slidingBuffer: [Float] = []
    private var lastProcessTime: Date = .distantPast
    private var lastEmittedText: String = ""

    // MARK: - Public

    func start(player: AVPlayer) {
        stop()
        isActive = true

        let extractor = AudioExtractor()
        self.audioExtractor = extractor

        processingTask = Task { [weak self] in
            guard let self else { return }
            await MainActor.run { self.pipelineStatus = "加载 Whisper..." }

            // Load Whisper
            if self.whisperService == nil {
                let service = WhisperService()
                do {
                    try await service.loadModels()
                    await MainActor.run {
                        self.whisperService = service
                        self.pipelineStatus = "Whisper OK"
                    }
                } catch {
                    await MainActor.run {
                        self.pipelineStatus = "Whisper 失败: \(error.localizedDescription)"
                    }
                    return
                }
            }

            // Load translation model in the background — transcription can run without it.
            if self.translationService == nil {
                let ts = TranslationService()
                await ts.prepare()
                await MainActor.run { self.translationService = ts }
            }

            // Set up audio callback
            extractor.setAudioCallback { [weak self] buffer in
                Task { @MainActor [weak self] in
                    self?.enqueueAudio(buffer)
                }
            }
            extractor.start(player: player)
            await MainActor.run { self.pipelineStatus = "等待音频..." }

            // Monitor extractor health
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                let err = extractor.lastError
                if err.hasPrefix("无") || err.hasPrefix("Tap 创建失败") || err.hasPrefix("轨道") {
                    await MainActor.run { self.pipelineStatus = err }
                }
            }
        }
    }

    func stop() {
        processingTask?.cancel()
        processingTask = nil
        audioExtractor?.stop()
        audioExtractor = nil
        slidingBuffer.removeAll()
        lastEmittedText = ""
        isActive = false
        currentOriginalText = ""
        currentTranslatedText = ""
        pipelineStatus = "等待启动"
    }

    // MARK: - Sliding Window Audio Processing

    private func enqueueAudio(_ buffer: [Float]) {
        slidingBuffer.append(contentsOf: buffer)
        if slidingBuffer.count > windowSize {
            slidingBuffer.removeFirst(slidingBuffer.count - windowSize)
        }

        let now = Date()
        guard now.timeIntervalSince(lastProcessTime) >= 1.0 else { return }
        guard slidingBuffer.count >= 16000 else { return }
        guard let whisper = whisperService else {
            pipelineStatus = "Whisper 未就绪"
            return
        }

        lastProcessTime = now
        let snapshot = Array(slidingBuffer)

        Task {
            pipelineStatus = "识别中..."
            let start = CFAbsoluteTimeGetCurrent()
            let text = await whisper.transcribe(audioSamples: snapshot)
            let elapsed = CFAbsoluteTimeGetCurrent() - start
            let cleaned = Self.cleanTranscription(text)

            guard !cleaned.isEmpty else {
                pipelineStatus = String(format: "静音 %.1fs", elapsed)
                return
            }
            // Skip if the sliding window produced the same text again.
            guard cleaned != lastEmittedText else {
                pipelineStatus = String(format: "✓ %.1fs", elapsed)
                return
            }
            lastEmittedText = cleaned

            currentOriginalText = cleaned
            pipelineStatus = String(format: "✓ %.1fs", elapsed)

            // Translate async
            if let ts = translationService {
                Task {
                    if let result = await ts.translate(cleaned), !result.isEmpty {
                        await MainActor.run { [weak self] in
                            guard self?.lastEmittedText == cleaned else { return }
                            self?.currentTranslatedText = result
                        }
                    }
                }
            }
        }
    }

    // MARK: - Text Cleaning

    private static func cleanTranscription(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let stripped = trimmed.replacingOccurrences(of: ".", with: "")
                              .replacingOccurrences(of: " ", with: "")
        if stripped.isEmpty { return "" }
        return trimmed
    }
}
