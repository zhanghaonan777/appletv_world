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
    @Published var displayMode: SubtitleDisplayMode = .both

    // MARK: - Private

    private var audioExtractor: AudioExtractor?
    private var audioBufferQueue: [[Float]] = []
    private var processingTask: Task<Void, Never>?
    private var whisperService: WhisperService?
    private var translationService: Any? // TranslationService (type-erased for availability)

    private let minSamplesForProcessing: Int = 32000 // ~2s at 16kHz

    // MARK: - Public

    func start(streamURL: URL) {
        stop()
        isActive = true

        let extractor = AudioExtractor()
        self.audioExtractor = extractor

        processingTask = Task { [weak self] in
            print("[SubtitleEngine] Task started")

            // Load Whisper
            if self?.whisperService == nil {
                print("[SubtitleEngine] Loading Whisper...")
                let service = WhisperService()
                do {
                    try await service.loadModels()
                    await MainActor.run { self?.whisperService = service }
                    print("[SubtitleEngine] Whisper loaded OK")
                } catch {
                    print("[SubtitleEngine] Whisper FAILED: \(error)")
                }
            }

            // Load Translation
            if self?.translationService == nil {
                print("[SubtitleEngine] Loading Translation...")
                let ts = TranslationService()
                await ts.prepare()
                await MainActor.run { self?.translationService = ts }
                print("[SubtitleEngine] Translation loaded OK")
            }

            print("[SubtitleEngine] Setting up audio callback...")
            extractor.setAudioCallback { [weak self] buffer in
                print("[SubtitleEngine] Got \(buffer.count) audio samples!")
                Task { @MainActor [weak self] in
                    self?.enqueueAudio(buffer)
                }
            }

            print("[SubtitleEngine] Starting extractor for \(streamURL)")
            extractor.start(url: streamURL)
            print("[SubtitleEngine] Extractor started, entering monitor loop")

            // Monitor extractor status
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                print("[SubtitleEngine] extractor status: \(extractor.lastError)")
            }
        }
    }

    func stop() {
        processingTask?.cancel()
        processingTask = nil
        audioExtractor?.stop()
        audioExtractor = nil
        audioBufferQueue.removeAll()
        isActive = false
        currentOriginalText = ""
        currentTranslatedText = ""
    }

    // MARK: - Audio Processing

    private func enqueueAudio(_ buffer: [Float]) {
        audioBufferQueue.append(buffer)

        let totalSamples = audioBufferQueue.reduce(0) { $0 + $1.count }
        if totalSamples >= minSamplesForProcessing {
            let combined = audioBufferQueue.flatMap { $0 }
            audioBufferQueue.removeAll()
            processAudio(combined)
        }
    }

    private func processAudio(_ buffer: [Float]) {
        guard let whisper = whisperService else {
            currentOriginalText = ""
            currentTranslatedText = ""
            return
        }

        Task {
            // 1. Transcribe
            let text = await whisper.transcribe(audioSamples: buffer)

            // 2. Translate
            var translated = ""
            if !text.isEmpty, let ts = self.translationService as? TranslationService {
                translated = await ts.translate(text) ?? ""
            }

            // 3. Update UI
            await MainActor.run { [weak self] in
                // Filter out filler tokens like repeated "..."
                let cleaned = Self.cleanTranscription(text)
                self?.currentOriginalText = cleaned
                self?.currentTranslatedText = translated
            }
        }
    }

    // MARK: - Text Cleaning

    /// Remove Whisper filler patterns (repeated "...", single dots, etc.)
    private static func cleanTranscription(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // If it's all dots/periods/spaces, treat as silence
        let stripped = trimmed.replacingOccurrences(of: ".", with: "")
                              .replacingOccurrences(of: " ", with: "")
        if stripped.isEmpty { return "" }

        return trimmed
    }
}
