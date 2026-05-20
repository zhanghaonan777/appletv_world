import Foundation
import SwiftWhisper

// MARK: - WhisperService

/// Real-time speech recognition using whisper.cpp via SwiftWhisper.
actor WhisperService {

    static let sampleRate: Int = 16000

    private var whisper: Whisper?
    private var isLoaded: Bool = false

    // MARK: - Public API

    func loadModels() async throws {
        guard !isLoaded else { return }

        guard let modelPath = locateModelFile() else {
            throw WhisperError.modelsNotFound
        }

        NSLog("[Whisper] Loading model: %@", modelPath)

        let modelURL = URL(fileURLWithPath: modelPath)
        whisper = Whisper(fromFileURL: modelURL)

        isLoaded = true
        NSLog("[Whisper] Model loaded OK")
    }

    /// Transcribe audio samples (16kHz mono Float32).
    func transcribe(audioSamples: [Float]) async -> String {
        guard let whisper else { return "" }

        do {
            let segments = try await whisper.transcribe(audioFrames: audioSamples)
            let text = segments.map(\.text).joined(separator: " ")
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            NSLog("[Whisper] Transcription error: %@", error.localizedDescription)
            return ""
        }
    }

    // MARK: - Model Location

    private func locateModelFile() -> String? {
        if let path = Bundle.main.path(forResource: "ggml-tiny", ofType: "bin") {
            return path
        }

        #if DEBUG
        let devPath = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Models/WhisperTiny/ggml-tiny.bin")
        if FileManager.default.fileExists(atPath: devPath.path) {
            return devPath.path
        }
        #endif

        return nil
    }

    enum WhisperError: Error {
        case modelsNotFound
    }
}
