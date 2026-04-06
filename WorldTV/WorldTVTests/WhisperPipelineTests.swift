import XCTest
@testable import WorldTV

final class WhisperPipelineTests: XCTestCase {

    private var whisper: WhisperService!

    override func setUp() async throws {
        whisper = WhisperService()
        try await whisper.loadModels()
    }

    // MARK: - Silence → should produce empty or filler text, not crash

    func testSilenceTranscription() async throws {
        let silence = [Float](repeating: 0.0, count: 32000) // 2s
        let result = await whisper.transcribe(audioSamples: silence)
        // Whisper outputs "..." for silence — just verify it doesn't crash and returns something
        XCTAssertNotNil(result)
        print("[Test] Silence result: '\(result)'")
    }

    // MARK: - Sine wave → validates full pipeline without crash

    func testSineWaveTranscription() async throws {
        let sampleRate: Float = 16000
        let duration: Float = 3.0
        let freq: Float = 440.0
        let count = Int(sampleRate * duration)
        var samples = [Float](repeating: 0, count: count)
        for i in 0..<count {
            samples[i] = 0.3 * sin(2.0 * .pi * freq * Float(i) / sampleRate)
        }

        let result = await whisper.transcribe(audioSamples: samples)
        XCTAssertNotNil(result)
        print("[Test] Sine wave result: '\(result)'")
    }

    // MARK: - Very short audio → padding works

    func testShortAudioPadding() async throws {
        let shortSamples = [Float](repeating: 0.1, count: 1600) // 0.1s
        let result = await whisper.transcribe(audioSamples: shortSamples)
        XCTAssertNotNil(result)
        print("[Test] Short audio result: '\(result)'")
    }

    // MARK: - Full 30s audio → no OOM or timeout

    func testFull30sAudio() async throws {
        var noise = [Float](repeating: 0, count: 480000) // 30s
        for i in 0..<noise.count {
            noise[i] = Float.random(in: -0.05...0.05)
        }

        let start = CFAbsoluteTimeGetCurrent()
        let result = await whisper.transcribe(audioSamples: noise)
        let elapsed = CFAbsoluteTimeGetCurrent() - start

        XCTAssertNotNil(result)
        print("[Test] 30s noise result: '\(result)' in \(String(format: "%.1f", elapsed))s")
        // Should complete in reasonable time (< 30s on simulator)
        XCTAssertLessThan(elapsed, 30.0, "Transcription took too long")
    }

    // MARK: - Multiple sequential transcriptions → no state leak

    func testSequentialTranscriptions() async throws {
        let silence = [Float](repeating: 0.0, count: 32000)
        let r1 = await whisper.transcribe(audioSamples: silence)
        let r2 = await whisper.transcribe(audioSamples: silence)

        // Same input should give same output (deterministic greedy decode)
        XCTAssertEqual(r1, r2, "Sequential transcriptions of same input should be identical")
        print("[Test] Sequential: '\(r1)' == '\(r2)'")
    }
}
