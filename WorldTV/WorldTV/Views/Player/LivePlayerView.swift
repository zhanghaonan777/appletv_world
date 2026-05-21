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

/// Fullscreen TV-style player. A dumb view: it renders `appModel.currentChannel`,
/// forwards remote input to `appModel`, and pauses when the model says the
/// video is covered. Focus is driven by the root view.
struct LivePlayerView: View {
    let appModel: AppModel
    let channels: [Channel]

    @StateObject private var model = LivePlayerModel()
    @StateObject private var captions = CaptionOutput()

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

            // Broadcast closed captions — shown automatically whenever the
            // channel carries a CC / subtitle track.
            if !captions.text.isEmpty {
                VStack {
                    Spacer()
                    Text(captions.text)
                        .font(.system(size: 32, weight: .semibold))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 26)
                        .padding(.vertical, 12)
                        .background(Color.black.opacity(0.65))
                        .cornerRadius(8)
                        .padding(.bottom, 90)
                }
                .allowsHitTesting(false)
            }
        }
        .focusable()
        .onMoveCommand { direction in
            switch direction {
            case .up:            appModel.handle(.up, channels: channels)
            case .down:          appModel.handle(.down, channels: channels)
            case .left:          appModel.handle(.left, channels: channels)
            case .right:         appModel.handle(.right, channels: channels)
            @unknown default:    break
            }
        }
        .onExitCommand { appModel.handle(.menu, channels: channels) }
        .onTapGesture { appModel.handle(.select, channels: channels) }
        .onAppear { playCurrentChannel() }
        .onDisappear {
            model.stop()
            captions.detach()
        }
        .onChange(of: appModel.currentChannel?.id) { _, _ in
            playCurrentChannel()
        }
        .onChange(of: appModel.isVideoCovered) { _, covered in
            if covered { model.pause() } else { model.resume() }
        }
    }

    private func playCurrentChannel() {
        guard let channel = appModel.currentChannel else { return }
        model.play(channel)
        channel.lastWatched = Date()
        if let item = model.player.currentItem {
            captions.attach(to: item)
        }
    }
}
