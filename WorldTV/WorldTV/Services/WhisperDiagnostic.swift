import Foundation
import CoreML

/// Offline diagnostic to verify the Whisper CoreML pipeline end-to-end.
/// Call `WhisperDiagnostic.run()` once at startup to confirm models load and inference succeeds.
enum WhisperDiagnostic {

    @MainActor
    static func run() {
        Task {
            NSLog("[WhisperDiag] === Starting Whisper Pipeline Diagnostic ===")

            // Step 1: Check model files in bundle
            let modelDir = Bundle.main.resourceURL?.appendingPathComponent("openai_whisper-tiny.en")
            if let dir = modelDir {
                let fm = FileManager.default
                let melExists = fm.fileExists(atPath: dir.appendingPathComponent("MelSpectrogram.mlmodelc").path)
                let encExists = fm.fileExists(atPath: dir.appendingPathComponent("AudioEncoder.mlmodelc").path)
                let decExists = fm.fileExists(atPath: dir.appendingPathComponent("TextDecoder.mlmodelc").path)
                let vocabExists = fm.fileExists(atPath: dir.appendingPathComponent("vocab.json").path)
                NSLog("[WhisperDiag] Model dir: %@", dir.path)
                NSLog("[WhisperDiag] Mel:%@ Enc:%@ Dec:%@ Vocab:%@",
                      melExists ? "OK" : "MISSING",
                      encExists ? "OK" : "MISSING",
                      decExists ? "OK" : "MISSING",
                      vocabExists ? "OK" : "MISSING")

                if !melExists || !encExists || !decExists {
                    NSLog("[WhisperDiag] FAIL: Missing model files!")
                    return
                }
            } else {
                NSLog("[WhisperDiag] FAIL: Bundle resourceURL is nil")
                return
            }

            // Step 2: Load models via WhisperService
            NSLog("[WhisperDiag] Loading WhisperService...")
            let whisper = WhisperService()
            do {
                try await whisper.loadModels()
                NSLog("[WhisperDiag] Model loading: OK")
            } catch {
                NSLog("[WhisperDiag] FAIL: Model loading error: %@", error.localizedDescription)
                return
            }

            // Step 3: Test with silence only (should quickly hit EOT)
            NSLog("[WhisperDiag] Testing with 2s silence...")
            let t0 = CFAbsoluteTimeGetCurrent()
            let silenceSamples = [Float](repeating: 0.0, count: 32000)
            let silenceResult = await whisper.transcribe(audioSamples: silenceSamples)
            let elapsed = CFAbsoluteTimeGetCurrent() - t0
            NSLog("[WhisperDiag] Silence result: '%@' (len=%d) in %.1fs", silenceResult, silenceResult.count, elapsed)

            NSLog("[WhisperDiag] === Diagnostic Complete ===")
        }
    }
}
