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

/// Drives the AI subtitle pipeline: tap audio on the Apple TV, stream it to the
/// Mac subtitle server, and display the transcription / translation it returns.
@MainActor
class SubtitleEngine: ObservableObject {

    static let serverURLKey = "subtitleServerURL"

    // MARK: - Published State

    @Published var currentOriginalText: String = ""
    @Published var currentTranslatedText: String = ""
    @Published var isActive: Bool = false
    @Published var sourceLanguage: String = "auto"
    @Published var targetLanguage: String = "zh"
    @Published var pipelineStatus: String = "等待启动"
    @Published var displayMode: SubtitleDisplayMode = .both

    // MARK: - Private

    private var audioExtractor: AudioExtractor?
    private let client = RemoteSubtitleClient()

    // MARK: - Public

    func start(player: AVPlayer) {
        stop()
        isActive = true

        guard let url = Self.serverURL() else {
            pipelineStatus = "未配置字幕服务器地址(设置里填)"
            return
        }

        client.connect(
            to: url,
            onSubtitle: { [weak self] subtitle in
                Task { @MainActor in
                    guard let self else { return }
                    if !subtitle.original.isEmpty { self.currentOriginalText = subtitle.original }
                    if !subtitle.translated.isEmpty { self.currentTranslatedText = subtitle.translated }
                    self.pipelineStatus = "✓ 字幕中"
                }
            },
            onStatus: { [weak self] status in
                Task { @MainActor in self?.pipelineStatus = status }
            }
        )

        let extractor = AudioExtractor()
        audioExtractor = extractor
        let client = self.client
        extractor.setAudioCallback { buffer in
            client.send(buffer)
        }
        extractor.start(player: player)
        pipelineStatus = "连接字幕服务器…"
    }

    func stop() {
        audioExtractor?.stop()
        audioExtractor = nil
        client.disconnect()
        isActive = false
        currentOriginalText = ""
        currentTranslatedText = ""
        pipelineStatus = "等待启动"
    }

    // MARK: - Server Address

    /// The configured Mac subtitle server URL, e.g. `ws://192.168.1.20:8765`.
    static func serverURL() -> URL? {
        let raw = (UserDefaults.standard.string(forKey: serverURLKey) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty, let url = URL(string: raw), url.scheme != nil else { return nil }
        return url
    }
}
