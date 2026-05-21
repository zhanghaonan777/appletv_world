import SwiftUI
import AVFoundation

// MARK: - Playback State

enum PlaybackState: Equatable {
    case loading
    case playing
    case failed
}

// MARK: - Player Model

/// Owns the `AVPlayer` and tracks readiness of the current channel's stream.
@MainActor
final class LivePlayerModel: ObservableObject {
    @Published private(set) var state: PlaybackState = .loading
    let player = AVPlayer()

    private var statusObservation: NSKeyValueObservation?
    private var loadTimeout: Task<Void, Never>?

    init() {
        // Route audio through the playback category so video sound behaves
        // correctly (plays in silent mode, takes over the audio session).
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        try? AVAudioSession.sharedInstance().setActive(true)
    }

    func play(_ channel: Channel) {
        guard let url = URL(string: channel.streamURL) else {
            state = .failed
            return
        }
        state = .loading
        let item = AVPlayerItem(url: url)
        statusObservation = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            Task { @MainActor in
                switch item.status {
                case .readyToPlay:
                    self?.loadTimeout?.cancel()
                    self?.state = .playing
                case .failed:
                    self?.loadTimeout?.cancel()
                    self?.state = .failed
                default:
                    self?.state = .loading
                }
            }
        }
        // A dead IPTV source can stall in .loading forever — fail it after 15s.
        loadTimeout?.cancel()
        loadTimeout = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 15_000_000_000)
            guard !Task.isCancelled else { return }
            if self?.state == .loading { self?.state = .failed }
        }
        player.replaceCurrentItem(with: item)
        player.play()
    }

    func pause() {
        player.pause()
    }

    func resume() {
        player.play()
    }

    func stop() {
        player.pause()
        player.replaceCurrentItem(with: nil)
        statusObservation = nil
        loadTimeout?.cancel()
        loadTimeout = nil
    }
}

// MARK: - Live Player View

/// Fullscreen TV-style player: video surface, loading / error states,
/// channel up/down zapping, and (when enabled) the AI subtitle overlay.
struct LivePlayerView: View {
    let channel: Channel
    /// True when the player is the foreground layer (no overlay covering input).
    var isActive: Bool = true
    /// True when a fullscreen overlay (guide / settings) hides the video.
    var isCovered: Bool = false
    var onChannelUp: () -> Void = {}
    var onChannelDown: () -> Void = {}
    var onSelect: () -> Void = {}
    var onExit: () -> Void = {}

    @StateObject private var model = LivePlayerModel()
    @StateObject private var subtitleEngine = SubtitleEngine()
    @AppStorage("aiSubtitlesEnabled") private var aiSubtitlesEnabled = false
    @FocusState private var focused: Bool

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            PlayerLayerView(player: model.player)
                .ignoresSafeArea()

            switch model.state {
            case .loading:
                ProgressView()
                    .tint(.white)
                    .scaleEffect(1.5)
            case .failed:
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 60))
                        .foregroundColor(Theme.textSecondary)
                    Text("频道无法播放")
                        .font(.title3)
                        .foregroundColor(Theme.textPrimary)
                    Text("按上下键切换频道")
                        .font(.callout)
                        .foregroundColor(Theme.textSecondary)
                }
            case .playing:
                EmptyView()
            }

            if aiSubtitlesEnabled {
                SubtitleOverlayView(engine: subtitleEngine)
                    .ignoresSafeArea()
            }
        }
        .focusable()
        .focused($focused)
        .disabled(!isActive)
        .onMoveCommand { direction in
            switch direction {
            case .up:            onChannelUp()
            case .down:          onChannelDown()
            case .left, .right:  onSelect()
            @unknown default:    break
            }
        }
        .onExitCommand { onExit() }
        .onTapGesture { onSelect() }
        .onAppear {
            focused = true
            model.play(channel)
            channel.lastWatched = Date()
            startSubtitlesIfEnabled()
        }
        .onDisappear {
            model.stop()
            subtitleEngine.stop()
        }
        .onChange(of: channel.id) { _, _ in
            model.play(channel)
            channel.lastWatched = Date()
            restartSubtitles()
        }
        .onChange(of: isCovered) { _, covered in
            if covered { model.pause() } else { model.resume() }
        }
        .onChange(of: isActive) { _, active in
            // The player is permanently mounted, so re-grab focus whenever it
            // becomes the foreground layer again (an overlay just closed).
            if active {
                DispatchQueue.main.async { focused = true }
            }
        }
    }

    private func startSubtitlesIfEnabled() {
        guard aiSubtitlesEnabled else { return }
        subtitleEngine.start(player: model.player)
    }

    private func restartSubtitles() {
        subtitleEngine.stop()
        startSubtitlesIfEnabled()
    }
}
