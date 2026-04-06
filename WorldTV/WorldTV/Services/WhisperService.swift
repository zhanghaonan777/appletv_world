import Foundation
import CoreML

// MARK: - WhisperService

/// Performs on-device speech recognition using WhisperKit-format CoreML models.
///
/// Pipeline: Audio [Float] -> MelSpectrogram -> AudioEncoder -> TextDecoder (autoregressive greedy).
actor WhisperService {

    // MARK: - Constants

    static let sampleRate: Int = 16000
    static let windowSamples: Int = 30 * sampleRate  // 480000

    private static let sotToken: Int32 = 50257
    private static let eotToken: Int32 = 50256
    private static let noTimestampsToken: Int32 = 50362
    private static let maxDecodingSteps: Int = 224

    private static let suppressTokens: Set<Int> = Set([
        1, 2, 7, 8, 9, 10, 14, 25, 26, 27, 28, 29, 31, 58, 59, 60, 61, 62, 63,
        90, 91, 92, 93, 357, 366, 438, 532, 685, 705, 796, 930, 1058, 1220, 1267,
        1279, 1303, 1343, 1377, 1391, 1635, 1782, 1875, 2162, 2361, 2488, 3467,
        4008, 4211, 4600, 4808, 5299, 5855, 6329, 7203, 9609, 9959, 10563, 10786,
        11420, 11709, 11907, 13163, 13697, 13700, 14808, 15306, 16410, 16791,
        17992, 19203, 19510, 20724, 22305, 22935, 27007, 30109, 30420, 33409,
        34949, 40283, 40493, 40549, 47282, 49146, 50257, 50357, 50358, 50359,
        50360, 50361
    ])

    // MARK: - Models

    private var melSpectrogramModel: MLModel?
    private var audioEncoderModel: MLModel?
    private var textDecoderModel: MLModel?
    private var isLoaded: Bool = false

    // MARK: - Tokenizer

    private var tokenToString: [Int: String] = [:]
    private var _gpt2UnicodeToByte: [Character: UInt8] = [:]

    // MARK: - Public API

    func loadModels() async throws {
        guard !isLoaded else { return }

        guard let modelDir = locateModelDirectory() else {
            throw WhisperError.modelsNotFound
        }

        NSLog("[Whisper] Loading models from: %@", modelDir.path)

        let config = MLModelConfiguration()
        #if targetEnvironment(simulator)
        config.computeUnits = .cpuOnly
        #else
        config.computeUnits = .cpuAndNeuralEngine
        #endif

        melSpectrogramModel = try MLModel(contentsOf: modelDir.appendingPathComponent("MelSpectrogram.mlmodelc"), configuration: config)
        audioEncoderModel = try MLModel(contentsOf: modelDir.appendingPathComponent("AudioEncoder.mlmodelc"), configuration: config)
        textDecoderModel = try MLModel(contentsOf: modelDir.appendingPathComponent("TextDecoder.mlmodelc"), configuration: config)

        buildTokenizer()
        isLoaded = true
        NSLog("[Whisper] All models loaded.")
    }

    func transcribe(audioSamples: [Float]) async -> String {
        guard isLoaded,
              let melModel = melSpectrogramModel,
              let encModel = audioEncoderModel,
              let decModel = textDecoderModel
        else { return "" }

        do {
            let paddedAudio = prepareAudio(audioSamples)

            var t0 = CFAbsoluteTimeGetCurrent()
            let melFeatures = try computeMelSpectrogram(audio: paddedAudio, model: melModel)
            let melTime = CFAbsoluteTimeGetCurrent() - t0

            t0 = CFAbsoluteTimeGetCurrent()
            let encoderOutput = try encodeAudio(melFeatures: melFeatures, model: encModel)
            let encTime = CFAbsoluteTimeGetCurrent() - t0

            t0 = CFAbsoluteTimeGetCurrent()
            let tokens = try decodeGreedy(encoderOutput: encoderOutput, model: decModel)
            let decTime = CFAbsoluteTimeGetCurrent() - t0

            let text = detokenize(tokens).trimmingCharacters(in: .whitespacesAndNewlines)
            NSLog("[Whisper] mel=%.2fs enc=%.2fs dec=%.2fs (%d tok) -> '%@'", melTime, encTime, decTime, tokens.count, text)
            return text
        } catch {
            NSLog("[Whisper] Error: %@", error.localizedDescription)
            return ""
        }
    }

    // MARK: - Model Directory

    private func locateModelDirectory() -> URL? {
        if let bundlePath = Bundle.main.resourceURL?
            .appendingPathComponent("openai_whisper-tiny.en"),
           FileManager.default.fileExists(atPath: bundlePath.appendingPathComponent("MelSpectrogram.mlmodelc").path) {
            return bundlePath
        }

        if let bundlePath = Bundle.main.resourcePath {
            let candidate = URL(fileURLWithPath: bundlePath).appendingPathComponent("openai_whisper-tiny.en")
            if FileManager.default.fileExists(atPath: candidate.appendingPathComponent("MelSpectrogram.mlmodelc").path) {
                return candidate
            }
        }

        #if DEBUG
        let devPath = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Models/WhisperTiny/openai_whisper-tiny.en")
        if FileManager.default.fileExists(atPath: devPath.appendingPathComponent("MelSpectrogram.mlmodelc").path) {
            return devPath
        }
        #endif

        return nil
    }

    // MARK: - Pipeline

    private func prepareAudio(_ samples: [Float]) -> [Float] {
        let target = Self.windowSamples
        if samples.count >= target { return Array(samples.prefix(target)) }
        var padded = samples
        padded.append(contentsOf: [Float](repeating: 0, count: target - samples.count))
        return padded
    }

    private func computeMelSpectrogram(audio: [Float], model: MLModel) throws -> MLMultiArray {
        let audioArray = try MLMultiArray(shape: [NSNumber(value: Self.windowSamples)], dataType: .float32)
        let ptr = audioArray.dataPointer.bindMemory(to: Float.self, capacity: Self.windowSamples)
        for i in 0..<Self.windowSamples { ptr[i] = audio[i] }

        let input = try MLDictionaryFeatureProvider(dictionary: ["audio": audioArray])
        let result = try model.prediction(from: input)

        guard let melOutput = result.featureValue(for: "melspectrogram_features")?.multiArrayValue else {
            throw WhisperError.unexpectedModelOutput("MelSpectrogram missing melspectrogram_features")
        }
        return melOutput
    }

    private func encodeAudio(melFeatures: MLMultiArray, model: MLModel) throws -> MLMultiArray {
        let input = try MLDictionaryFeatureProvider(dictionary: ["melspectrogram_features": melFeatures])
        let result = try model.prediction(from: input)

        guard let encOutput = result.featureValue(for: "encoder_output_embeds")?.multiArrayValue else {
            throw WhisperError.unexpectedModelOutput("AudioEncoder missing encoder_output_embeds")
        }
        return encOutput
    }

    private func decodeGreedy(encoderOutput: MLMultiArray, model: MLModel) throws -> [Int] {
        let maxSeqLen = 448
        let kvDim = 1536

        let keyCache = try MLMultiArray(shape: [1, NSNumber(value: kvDim), 1, NSNumber(value: maxSeqLen)], dataType: .float16)
        let valueCache = try MLMultiArray(shape: [1, NSNumber(value: kvDim), 1, NSNumber(value: maxSeqLen)], dataType: .float16)
        zeroFill(keyCache)
        zeroFill(valueCache)

        let prefixTokens: [Int32] = [Self.sotToken, Self.noTimestampsToken]
        var generatedTokens: [Int] = []
        var cachePosition: Int32 = 0

        for step in 0..<(Self.maxDecodingSteps + prefixTokens.count) {
            let currentToken: Int32
            if step < prefixTokens.count {
                currentToken = prefixTokens[step]
            } else if let last = generatedTokens.last {
                currentToken = Int32(last)
            } else {
                break
            }

            let inputIds = try MLMultiArray(shape: [1], dataType: .int32)
            inputIds[0] = NSNumber(value: currentToken)

            let cacheLengthArr = try MLMultiArray(shape: [1], dataType: .int32)
            cacheLengthArr[0] = NSNumber(value: cachePosition)

            let kvMask = try MLMultiArray(shape: [1, NSNumber(value: maxSeqLen)], dataType: .float16)
            zeroFill(kvMask)
            kvMask[[0, NSNumber(value: cachePosition)] as [NSNumber]] = 1.0

            let paddingMask = try MLMultiArray(shape: [1, NSNumber(value: maxSeqLen)], dataType: .float16)
            for i in 0..<maxSeqLen {
                paddingMask[i] = (i <= Int(cachePosition)) ? 0.0 : -10000.0
            }

            let decoderInput = try MLDictionaryFeatureProvider(dictionary: [
                "input_ids": inputIds,
                "cache_length": cacheLengthArr,
                "key_cache": keyCache,
                "value_cache": valueCache,
                "kv_cache_update_mask": kvMask,
                "encoder_output_embeds": encoderOutput,
                "decoder_key_padding_mask": paddingMask,
            ])

            let output = try model.prediction(from: decoderInput)

            // Update KV cache
            if let keyUpdate = output.featureValue(for: "key_cache_updates")?.multiArrayValue,
               let valueUpdate = output.featureValue(for: "value_cache_updates")?.multiArrayValue {
                copyKVUpdate(from: keyUpdate, to: keyCache, at: Int(cachePosition), dim: kvDim)
                copyKVUpdate(from: valueUpdate, to: valueCache, at: Int(cachePosition), dim: kvDim)
            }

            cachePosition += 1

            if step >= prefixTokens.count - 1 {
                guard let logitsArray = output.featureValue(for: "logits")?.multiArrayValue else {
                    throw WhisperError.unexpectedModelOutput("TextDecoder missing logits")
                }

                let nextToken = greedyArgmax(logits: logitsArray)
                if nextToken == Int(Self.eotToken) { break }
                generatedTokens.append(nextToken)
            }
        }

        return generatedTokens
    }

    // MARK: - Argmax

    private func greedyArgmax(logits: MLMultiArray) -> Int {
        let vocabSize = logits.shape.count == 3 ? logits.shape[2].intValue : logits.count
        var bestIdx = 0
        var bestVal: Float = -.infinity

        for i in 0..<vocabSize {
            if Self.suppressTokens.contains(i) { continue }
            let val = logits[i].floatValue
            if val > bestVal {
                bestVal = val
                bestIdx = i
            }
        }
        return bestIdx
    }

    // MARK: - KV Cache

    private func copyKVUpdate(from update: MLMultiArray, to cache: MLMultiArray, at position: Int, dim: Int) {
        let maxSeqLen = cache.shape[3].intValue
        // Both are float16 — safe to copy as UInt16
        let updatePtr = update.dataPointer.assumingMemoryBound(to: UInt16.self)
        let cachePtr = cache.dataPointer.assumingMemoryBound(to: UInt16.self)
        for d in 0..<dim {
            cachePtr[d * maxSeqLen + position] = updatePtr[d]
        }
    }

    private func zeroFill(_ array: MLMultiArray) {
        memset(array.dataPointer, 0, array.count * 2) // float16 = 2 bytes
    }

    // MARK: - Tokenizer

    private func buildTokenizer() {
        var byteToUnicode: [Int: Character] = [:]
        var offset = 256
        for b in 0..<256 {
            if (33...126).contains(b) || (161...172).contains(b) || (174...255).contains(b) {
                byteToUnicode[b] = Character(UnicodeScalar(b)!)
            } else {
                byteToUnicode[b] = Character(UnicodeScalar(offset)!)
                offset += 1
            }
        }
        var unicodeToByte: [Character: UInt8] = [:]
        for (b, c) in byteToUnicode { unicodeToByte[c] = UInt8(b) }
        self._gpt2UnicodeToByte = unicodeToByte

        if let modelDir = locateModelDirectory() {
            let vocabURL = modelDir.appendingPathComponent("vocab.json")
            if let data = try? Data(contentsOf: vocabURL),
               let vocab = try? JSONSerialization.jsonObject(with: data) as? [String: Int] {
                for (text, id) in vocab { tokenToString[id] = text }
                NSLog("[Whisper] Loaded vocab.json (%d entries)", vocab.count)
                return
            }
        }
        NSLog("[Whisper] No vocab.json found, using fallback tokenizer")
    }

    private func detokenize(_ tokens: [Int]) -> String {
        guard !tokenToString.isEmpty else {
            return tokens.map { "[\($0)]" }.joined(separator: " ")
        }

        var bytes: [UInt8] = []
        for token in tokens {
            guard let piece = tokenToString[token] else { continue }
            for ch in piece {
                if let b = _gpt2UnicodeToByte[ch] {
                    bytes.append(b)
                } else if let scalar = ch.unicodeScalars.first, scalar.value < 256 {
                    bytes.append(UInt8(scalar.value))
                }
            }
        }
        return String(bytes: bytes, encoding: .utf8)?
            .replacingOccurrences(of: "<|endoftext|>", with: "")
            .replacingOccurrences(of: "<|startoftranscript|>", with: "")
            ?? ""
    }

    // MARK: - Errors

    enum WhisperError: LocalizedError {
        case modelsNotFound
        case unexpectedModelOutput(String)

        var errorDescription: String? {
            switch self {
            case .modelsNotFound:
                return "Whisper CoreML models not found in bundle."
            case .unexpectedModelOutput(let detail):
                return "Unexpected model output: \(detail)"
            }
        }
    }
}
