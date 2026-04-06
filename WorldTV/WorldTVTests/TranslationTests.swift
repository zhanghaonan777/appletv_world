import XCTest
import AVFoundation
import LlamaSwift
@testable import WorldTV

final class TranslationTests: XCTestCase {

    // MARK: - Dictionary Fallback Tests

    func testOfflineTranslation() async throws {
        let ts = TranslationService()
        await ts.prepare()

        let tests: [(input: String, expectedContains: String)] = [
            ("Breaking news today", "突发新闻"),
            ("The president announced a new plan", "总统"),
            ("Hello, welcome", "你好"),
            ("The economy is important", "经济"),
        ]

        for test in tests {
            let result = await ts.translate(test.input)
            XCTAssertNotNil(result, "Should return a result for: \(test.input)")
            if let result {
                print("[DictTest] '\(test.input)' → '\(result)'")
                XCTAssertTrue(result.contains(test.expectedContains),
                    "Expected '\(test.expectedContains)' in '\(test.input)', got: '\(result)'")
            }
        }
    }

    // MARK: - Qwen3.5 Model Translation Tests

    func testModelTranslation() async throws {
        // Load model from project path (not app bundle)
        let modelPath = findModelPath()
        guard let modelPath else {
            print("[ModelTest] GGUF not found, skipping model test")
            throw XCTSkip("Qwen3.5 GGUF not found at expected path")
        }

        print("[ModelTest] Found model: \(modelPath)")
        let ts = TranslationServiceTestHelper(modelPath: modelPath)
        await ts.prepare()

        let tests: [(input: String, lang: String)] = [
            ("Hello, how are you?", "Chinese"),
            ("The weather is sunny today.", "Chinese"),
            ("Breaking news: the president announced a new policy.", "Chinese"),
            ("Scientists have discovered water on Mars.", "Chinese"),
            ("The stock market dropped significantly.", "Japanese"),
        ]

        for test in tests {
            await ts.setTargetLanguage(test.lang)
            let start = CFAbsoluteTimeGetCurrent()
            let result = await ts.translate(test.input)
            let elapsed = CFAbsoluteTimeGetCurrent() - start

            print("[ModelTest] '\(test.input)'")
            print("  → \(test.lang): \(result ?? "nil")")
            print("  耗时: \(String(format: "%.2f", elapsed))s")

            XCTAssertNotNil(result, "Model should produce translation for: \(test.input)")

            if test.lang == "Chinese", let result {
                let hasChinese = result.unicodeScalars.contains { (0x4E00...0x9FFF).contains($0.value) }
                XCTAssertTrue(hasChinese, "Chinese translation should contain Chinese chars, got: '\(result)'")
            }
        }
    }

    func testModelTranslationLatency() async throws {
        let modelPath = findModelPath()
        guard let modelPath else {
            throw XCTSkip("Qwen3.5 GGUF not found")
        }

        let ts = TranslationServiceTestHelper(modelPath: modelPath)
        await ts.prepare()

        // Warm up
        _ = await ts.translate("Hello")

        // Measure latency
        let sentences = [
            "Good morning everyone.",
            "The economy grew by three percent last quarter.",
            "Scientists discovered a new species of deep sea fish.",
        ]

        var totalTime: Double = 0
        for sentence in sentences {
            let start = CFAbsoluteTimeGetCurrent()
            let result = await ts.translate(sentence)
            let elapsed = CFAbsoluteTimeGetCurrent() - start
            totalTime += elapsed
            print("[Latency] \(String(format: "%.2f", elapsed))s — '\(sentence)' → '\(result ?? "nil")'")
        }

        let avg = totalTime / Double(sentences.count)
        print("[Latency] Average: \(String(format: "%.2f", avg))s per sentence")
        // We want < 2s per sentence for subtitle use case
        XCTAssertLessThan(avg, 5.0, "Average translation should be under 5s (relaxed for simulator)")
    }

    // MARK: - End-to-End: Speech → Whisper → Translation

    func testSpeechToTranslation() async throws {
        let whisper = WhisperService()
        try await whisper.loadModels()
        let samples = try loadWAVSamples(named: "test_news", ext: "wav")
        let transcription = await whisper.transcribe(audioSamples: samples)
        print("[E2E] Transcription: '\(transcription)'")
        XCTAssertFalse(transcription.isEmpty, "Should transcribe speech")

        let ts = TranslationService()
        await ts.prepare()
        let translation = await ts.translate(transcription)
        print("[E2E] Translation: '\(translation ?? "nil")'")
        XCTAssertNotNil(translation, "Should translate transcription")
    }

    // MARK: - Helpers

    private func findModelPath() -> String? {
        // Look in Models/Qwen35 relative to the project
        let projectDir = URL(fileURLWithPath: #file)
            .deletingLastPathComponent() // WorldTVTests
            .deletingLastPathComponent() // WorldTV project
        let candidates = [
            projectDir.appendingPathComponent("../Models/Qwen35/Qwen3.5-0.8B-Q4_K_M.gguf").path,
            "/Users/haonanzhang/github/appletv_world/Models/Qwen35/Qwen3.5-0.8B-Q4_K_M.gguf",
        ]
        return candidates.first { FileManager.default.fileExists(atPath: $0) }
    }

    private func loadWAVSamples(named name: String, ext: String) throws -> [Float] {
        let testBundle = Bundle(for: type(of: self))
        guard let folderURL = testBundle.url(forResource: "TestResources", withExtension: nil) else {
            throw NSError(domain: "Test", code: 1, userInfo: [NSLocalizedDescriptionKey: "TestResources not found"])
        }
        let fileURL = folderURL.appendingPathComponent("\(name).\(ext)")
        let audioFile = try AVAudioFile(forReading: fileURL)
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false)!
        let frameCount = AVAudioFrameCount(audioFile.length)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
        try audioFile.read(into: buffer)
        return Array(UnsafeBufferPointer(start: buffer.floatChannelData![0], count: Int(buffer.frameLength)))
    }
}

// MARK: - Test Helper (loads model from arbitrary path)

/// Wrapper that allows loading the GGUF model from a test path instead of app bundle.
actor TranslationServiceTestHelper {
    private let modelPath: String
    private var llamaModel: OpaquePointer?
    private var llamaContext: OpaquePointer?
    private var sampler: UnsafeMutablePointer<llama_sampler>?
    private var targetLanguage: String = "Chinese"

    init(modelPath: String) {
        self.modelPath = modelPath
    }

    func prepare() async {
        llama_backend_init()

        var mp = llama_model_default_params()
        mp.n_gpu_layers = 0
        llamaModel = llama_model_load_from_file(modelPath, mp)
        guard let model = llamaModel else {
            NSLog("[TestHelper] Failed to load model from: \(modelPath)")
            return
        }

        var cp = llama_context_default_params()
        cp.n_ctx = 256
        cp.n_batch = 256
        cp.n_threads = 4
        cp.n_threads_batch = 4
        llamaContext = llama_init_from_model(model, cp)

        let sparams = llama_sampler_chain_default_params()
        sampler = llama_sampler_chain_init(sparams)
        llama_sampler_chain_add(sampler, llama_sampler_init_top_k(40))
        llama_sampler_chain_add(sampler, llama_sampler_init_top_p(0.9, 1))
        llama_sampler_chain_add(sampler, llama_sampler_init_temp(0.3))
        llama_sampler_chain_add(sampler, llama_sampler_init_greedy())

        NSLog("[TestHelper] Model loaded OK")
    }

    func setTargetLanguage(_ language: String) {
        targetLanguage = language
    }

    func translate(_ text: String) async -> String? {
        guard let model = llamaModel, let ctx = llamaContext, let smpl = sampler else { return nil }

        let vocab = llama_model_get_vocab(model)
        let prompt = "<|im_start|>user\n/no_think\nTranslate to \(targetLanguage). Only output the translation, nothing else.\n\(text)<|im_end|>\n<|im_start|>assistant\n"

        var tokens = [llama_token](repeating: 0, count: 256)
        let nPrompt = llama_tokenize(vocab, prompt, Int32(prompt.utf8.count), &tokens, 256, true, true)
        guard nPrompt > 0 else { return nil }

        if let memory = llama_get_memory(ctx) {
            llama_memory_clear(memory, false)
        }

        let promptBatch = llama_batch_get_one(&tokens, nPrompt)
        guard llama_decode(ctx, promptBatch) == 0 else { return nil }

        var output = ""
        for _ in 0..<64 {
            let newToken = llama_sampler_sample(smpl, ctx, -1)
            if llama_vocab_is_eog(vocab, newToken) { break }

            var buf = [CChar](repeating: 0, count: 128)
            let len = llama_token_to_piece(vocab, newToken, &buf, 128, 0, false)
            if len > 0 {
                buf[Int(len)] = 0
                let piece = String(cString: buf)
                if piece.contains("<|") { break }
                output += piece
            }

            var newTokenArr = [newToken]
            let nextBatch = llama_batch_get_one(&newTokenArr, 1)
            guard llama_decode(ctx, nextBatch) == 0 else { break }
        }

        llama_sampler_reset(smpl)
        let result = output.trimmingCharacters(in: .whitespacesAndNewlines)
        return result.isEmpty ? nil : result
    }
}
