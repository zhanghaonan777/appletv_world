import Foundation
import LlamaSwift

/// On-device translation using Qwen3.5-0.8B via llama.cpp.
actor TranslationService {

    private var llamaModel: OpaquePointer?
    private var llamaContext: OpaquePointer?
    private var sampler: UnsafeMutablePointer<llama_sampler>?
    private var isReady = false
    private var modelLoaded = false
    private var targetLanguage: String = "Chinese"

    func prepare() async {
        guard let modelPath = Bundle.main.path(forResource: "Qwen3.5-0.8B-Q4_K_M", ofType: "gguf") else {
            isReady = true
            return
        }

        // Load model on a thread with large stack (llama.cpp needs it)
        let result: Bool = await withCheckedContinuation { continuation in
            let thread = Thread {
                llama_backend_init()

                var mp = llama_model_default_params()
                mp.n_gpu_layers = 0
                mp.use_mmap = true

                let model = llama_model_load_from_file(modelPath, mp)
                guard let model else {
                    continuation.resume(returning: false)
                    return
                }

                var cp = llama_context_default_params()
                cp.n_ctx = 256
                cp.n_batch = 256
                cp.n_threads = 4
                cp.n_threads_batch = 4
                let ctx = llama_init_from_model(model, cp)
                guard ctx != nil else {
                    llama_model_free(model)
                    continuation.resume(returning: false)
                    return
                }

                let sparams = llama_sampler_chain_default_params()
                let smpl = llama_sampler_chain_init(sparams)
                llama_sampler_chain_add(smpl, llama_sampler_init_top_k(40))
                llama_sampler_chain_add(smpl, llama_sampler_init_top_p(0.9, 1))
                llama_sampler_chain_add(smpl, llama_sampler_init_temp(0.3))
                llama_sampler_chain_add(smpl, llama_sampler_init_greedy())

                self.llamaModel = model
                self.llamaContext = ctx
                self.sampler = smpl

                continuation.resume(returning: true)
            }
            thread.stackSize = 8 * 1024 * 1024
            thread.qualityOfService = .userInitiated
            thread.start()
        }

        modelLoaded = result
        isReady = true
    }

    func setTargetLanguage(_ language: String) {
        targetLanguage = language
    }

    func translate(_ text: String) async -> String? {
        guard !text.isEmpty else { return nil }
        if !isReady { return "[模型加载中...]" }
        if modelLoaded, let r = translateWithModel(text) { return r }
        return nil
    }

    // MARK: - Model Translation

    private func translateWithModel(_ text: String) -> String? {
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
