import XCTest
import AVFoundation
@testable import WorldTV

final class WhisperSpeechTests: XCTestCase {

    private var whisper: WhisperService!

    override func setUp() async throws {
        whisper = WhisperService()
        try await whisper.loadModels()
    }

    // MARK: - Real Speech: "Hello, this is a test of the whisper speech recognition system..."

    func testRealSpeechTranscription() async throws {
        let samples = try loadWAVSamples(named: "test_speech", ext: "wav")
        XCTAssertGreaterThan(samples.count, 16000, "Audio should be at least 1 second")

        let start = CFAbsoluteTimeGetCurrent()
        let result = await whisper.transcribe(audioSamples: samples)
        let elapsed = CFAbsoluteTimeGetCurrent() - start

        print("[SpeechTest] Input: \(samples.count) samples (\(String(format: "%.1f", Double(samples.count)/16000.0))s)")
        print("[SpeechTest] Result: '\(result)'")
        print("[SpeechTest] Time: \(String(format: "%.2f", elapsed))s")

        XCTAssertFalse(result.isEmpty, "Should transcribe something from real speech")
        // Check for at least some expected words (case-insensitive)
        let lower = result.lowercased()
        let hasExpectedContent = lower.contains("hello") ||
                                 lower.contains("test") ||
                                 lower.contains("whisper") ||
                                 lower.contains("fox") ||
                                 lower.contains("speech")
        XCTAssertTrue(hasExpectedContent, "Should recognize at least one expected word, got: '\(result)'")
    }

    // MARK: - News Speech: "Breaking news today..."

    func testNewsSpeechTranscription() async throws {
        let samples = try loadWAVSamples(named: "test_news", ext: "wav")
        XCTAssertGreaterThan(samples.count, 16000)

        let start = CFAbsoluteTimeGetCurrent()
        let result = await whisper.transcribe(audioSamples: samples)
        let elapsed = CFAbsoluteTimeGetCurrent() - start

        print("[NewsTest] Input: \(samples.count) samples (\(String(format: "%.1f", Double(samples.count)/16000.0))s)")
        print("[NewsTest] Result: '\(result)'")
        print("[NewsTest] Time: \(String(format: "%.2f", elapsed))s")

        XCTAssertFalse(result.isEmpty, "Should transcribe something from news speech")
        let lower = result.lowercased()
        let hasExpectedContent = lower.contains("news") ||
                                 lower.contains("president") ||
                                 lower.contains("economy") ||
                                 lower.contains("scientist") ||
                                 lower.contains("ocean")
        XCTAssertTrue(hasExpectedContent, "Should recognize at least one expected word, got: '\(result)'")
    }

    // MARK: - Helper: Load WAV as Float32 samples

    private func loadWAVSamples(named name: String, ext: String) throws -> [Float] {
        // Test resources are in the test bundle's TestResources folder reference
        let testBundle = Bundle(for: type(of: self))
        guard let folderURL = testBundle.url(forResource: "TestResources", withExtension: nil) else {
            throw NSError(domain: "Test", code: 1, userInfo: [NSLocalizedDescriptionKey: "TestResources folder not found in test bundle"])
        }
        let fileURL = folderURL.appendingPathComponent("\(name).\(ext)")
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw NSError(domain: "Test", code: 2, userInfo: [NSLocalizedDescriptionKey: "File not found: \(fileURL.path)"])
        }

        let audioFile = try AVAudioFile(forReading: fileURL)
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false)!
        let frameCount = AVAudioFrameCount(audioFile.length)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            throw NSError(domain: "Test", code: 3, userInfo: [NSLocalizedDescriptionKey: "Cannot create PCM buffer"])
        }

        try audioFile.read(into: buffer)
        guard let channelData = buffer.floatChannelData else {
            throw NSError(domain: "Test", code: 4, userInfo: [NSLocalizedDescriptionKey: "No channel data"])
        }

        return Array(UnsafeBufferPointer(start: channelData[0], count: Int(buffer.frameLength)))
    }
}
