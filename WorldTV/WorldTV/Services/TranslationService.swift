import Foundation
import NaturalLanguage
import LlamaSwift

/// On-device translation using Qwen3.5-0.8B via llama.cpp.
/// Falls back to offline dictionary if model loading fails.
actor TranslationService {

    private var llamaModel: OpaquePointer?
    private var llamaContext: OpaquePointer?
    private var sampler: UnsafeMutablePointer<llama_sampler>?
    private var isReady = false
    private var targetLanguage: String = "Chinese"

    func prepare() async {
        NSLog("[Translation] Loading Qwen3.5 model...")

        guard let modelPath = Bundle.main.path(forResource: "Qwen3.5-0.8B-Q4_K_M", ofType: "gguf") else {
            NSLog("[Translation] GGUF not found in bundle, dictionary fallback")
            isReady = true
            return
        }

        llama_backend_init()

        var mp = llama_model_default_params()
        mp.n_gpu_layers = 0
        llamaModel = llama_model_load_from_file(modelPath, mp)
        guard let model = llamaModel else {
            NSLog("[Translation] Failed to load model")
            isReady = true
            return
        }

        var cp = llama_context_default_params()
        cp.n_ctx = 256
        cp.n_batch = 256
        cp.n_threads = 4
        cp.n_threads_batch = 4
        llamaContext = llama_init_from_model(model, cp)
        guard llamaContext != nil else {
            NSLog("[Translation] Failed to create context")
            isReady = true
            return
        }

        // Set up sampler chain: top-k -> top-p -> temp -> greedy
        let sparams = llama_sampler_chain_default_params()
        sampler = llama_sampler_chain_init(sparams)
        llama_sampler_chain_add(sampler, llama_sampler_init_top_k(40))
        llama_sampler_chain_add(sampler, llama_sampler_init_top_p(0.9, 1))
        llama_sampler_chain_add(sampler, llama_sampler_init_temp(0.3))
        llama_sampler_chain_add(sampler, llama_sampler_init_greedy())

        NSLog("[Translation] Qwen3.5 loaded OK")
        isReady = true
    }

    func setTargetLanguage(_ language: String) {
        targetLanguage = language
    }

    func translate(_ text: String) async -> String? {
        guard isReady, !text.isEmpty else { return nil }
        if let r = translateWithModel(text) { return r }
        return offlineTranslate(text)
    }

    // MARK: - Model Translation

    private func translateWithModel(_ text: String) -> String? {
        guard let model = llamaModel, let ctx = llamaContext, let smpl = sampler else { return nil }

        let vocab = llama_model_get_vocab(model)
        let prompt = "<|im_start|>user\n/no_think\nTranslate to \(targetLanguage). Only output the translation, nothing else.\n\(text)<|im_end|>\n<|im_start|>assistant\n"

        // Tokenize
        var tokens = [llama_token](repeating: 0, count: 256)
        let nPrompt = llama_tokenize(vocab, prompt, Int32(prompt.utf8.count), &tokens, 256, true, true)
        guard nPrompt > 0 else { return nil }

        // Clear memory state
        if let memory = llama_get_memory(ctx) {
            llama_memory_clear(memory, false)
        }

        // Decode prompt
        let promptBatch = llama_batch_get_one(&tokens, nPrompt)
        guard llama_decode(ctx, promptBatch) == 0 else {
            NSLog("[Translation] Prompt decode failed")
            return nil
        }

        // Generate
        var output = ""
        for _ in 0..<64 {
            let newToken = llama_sampler_sample(smpl, ctx, -1)

            if llama_vocab_is_eog(vocab, newToken) { break }

            // Token to text
            var buf = [CChar](repeating: 0, count: 128)
            let len = llama_token_to_piece(vocab, newToken, &buf, 128, 0, false)
            if len > 0 {
                buf[Int(len)] = 0
                let piece = String(cString: buf)
                if piece.contains("<|") { break }
                output += piece
            }

            // Decode new token
            var newTokenArr = [newToken]
            let nextBatch = llama_batch_get_one(&newTokenArr, 1)
            guard llama_decode(ctx, nextBatch) == 0 else { break }
        }

        llama_sampler_reset(smpl)

        let result = output.trimmingCharacters(in: .whitespacesAndNewlines)
        return result.isEmpty ? nil : result
    }

    // MARK: - Offline Fallback

    private func offlineTranslate(_ text: String) -> String {
        var result = text.lowercased()
        for (en, zh) in Self.commonPhrases {
            result = result.replacingOccurrences(of: en, with: zh)
        }
        if result != text.lowercased() { return result }
        return "[翻译] \(text)"
    }

    private static let commonPhrases: [(String, String)] = [
        ("hello", "你好"), ("good morning", "早上好"), ("good evening", "晚上好"),
        ("thank you", "谢谢"), ("welcome", "欢迎"), ("breaking news", "突发新闻"),
        ("the president", "总统"), ("government", "政府"), ("economy", "经济"),
        ("united states", "美国"), ("china", "中国"), ("today", "今天"),
        ("weather", "天气"), ("people", "人们"), ("world", "世界"),
    ]
}
