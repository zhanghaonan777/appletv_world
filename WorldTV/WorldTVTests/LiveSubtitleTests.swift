import XCTest
import AVFoundation
@testable import WorldTV

/// Simulates a live subtitle scenario:
/// Feeds audio in real-time chunks and measures Whisper latency + sync quality.
final class LiveSubtitleTests: XCTestCase {

    func testLiveStreamSimulation() async throws {
        // 1. Load Whisper
        let whisper = WhisperService()
        try await whisper.loadModels()
        print("[Live] Whisper loaded")

        // 2. Load test audio
        let samples = try loadWAVSamples(named: "test_news", ext: "wav")
        let sampleRate = 16000
        print("[Live] Audio loaded: \(samples.count) samples (\(String(format: "%.1f", Double(samples.count) / Double(sampleRate)))s)")

        // 3. Simulate real-time streaming with sliding window
        let windowSize = 48000  // 3 seconds
        let stepSize = 16000    // 1 second step
        let chunkSize = 3200    // 200ms chunks (simulating AudioExtractor callback)

        var slidingBuffer: [Float] = []
        var lastProcessTime = CFAbsoluteTimeGetCurrent()
        var totalInferences = 0
        var totalInferenceTime: Double = 0
        var results: [(simTime: Double, inferTime: Double, text: String)] = []

        let simStart = CFAbsoluteTimeGetCurrent()

        // Feed audio in 200ms chunks
        var offset = 0
        while offset < samples.count {
            let end = min(offset + chunkSize, samples.count)
            let chunk = Array(samples[offset..<end])

            // Add to sliding buffer
            slidingBuffer.append(contentsOf: chunk)
            if slidingBuffer.count > windowSize {
                slidingBuffer.removeFirst(slidingBuffer.count - windowSize)
            }

            let now = CFAbsoluteTimeGetCurrent()
            let simTime = now - simStart

            // Process every ~1 second
            if now - lastProcessTime >= 1.0 && slidingBuffer.count >= 16000 {
                lastProcessTime = now

                let snapshot = slidingBuffer
                let inferStart = CFAbsoluteTimeGetCurrent()
                let text = await whisper.transcribe(audioSamples: snapshot)
                let inferTime = CFAbsoluteTimeGetCurrent() - inferStart

                let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !cleaned.isEmpty {
                    totalInferences += 1
                    totalInferenceTime += inferTime
                    results.append((simTime: simTime, inferTime: inferTime, text: cleaned))
                    print(String(format: "[Live] t=%.1fs infer=%.2fs: %@", simTime, inferTime, cleaned))
                }
            }

            offset = end
            // Simulate real-time: wait proportional to chunk duration
            // (compressed: 10x faster than real-time for testing)
            try await Task.sleep(nanoseconds: 20_000_000) // 20ms per 200ms chunk = 10x speed
        }

        // Summary
        let avgInfer = totalInferences > 0 ? totalInferenceTime / Double(totalInferences) : 0
        print("\n=== Live Subtitle Simulation Results ===")
        print("Total inferences: \(totalInferences)")
        print(String(format: "Average inference time: %.2fs", avgInfer))
        print(String(format: "Total audio: %.1fs", Double(samples.count) / Double(sampleRate)))
        print("Window: \(windowSize / sampleRate)s, Step: ~1s")
        print("\nTimeline:")
        for r in results {
            print(String(format: "  [%.1fs] (%.2fs) %@", r.simTime, r.inferTime, r.text))
        }

        // Write results to file for retrieval
        var report = "=== Live Subtitle Simulation ===\n"
        report += "Inferences: \(totalInferences)\n"
        report += String(format: "Avg inference: %.2fs\n", avgInfer)
        report += String(format: "Audio: %.1fs\n", Double(samples.count) / Double(sampleRate))
        report += "Window: 3s, Step: ~1s\n\n"
        for r in results {
            report += String(format: "[%.1fs] (%.2fs) %@\n", r.simTime, r.inferTime, r.text)
        }
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        try report.write(to: docs.appendingPathComponent("live_test_report.txt"), atomically: true, encoding: .utf8)

        // Assertions
        XCTAssertGreaterThan(totalInferences, 0, "Should produce at least one transcription")
        XCTAssertLessThan(avgInfer, 5.0, "Avg inference under 5s, got \(String(format: "%.2f", avgInfer))s")
    }

    func testWhisperLatencyBenchmark() async throws {
        let whisper = WhisperService()
        try await whisper.loadModels()

        let samples = try loadWAVSamples(named: "test_speech", ext: "wav")

        // Test different window sizes
        let windows = [16000, 32000, 48000, 80000] // 1s, 2s, 3s, 5s

        var report = "=== Whisper Latency Benchmark ===\n"
        for w in windows {
            let chunk = Array(samples.prefix(w))
            let start = CFAbsoluteTimeGetCurrent()
            let text = await whisper.transcribe(audioSamples: chunk)
            let elapsed = CFAbsoluteTimeGetCurrent() - start
            let line = String(format: "%ds window: %.2fs → \"%@\"", w / 16000, elapsed, String(text.prefix(50)))
            report += line + "\n"
        }
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        try report.write(to: docs.appendingPathComponent("benchmark_report.txt"), atomically: true, encoding: .utf8)
    }

    // MARK: - Helper

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
