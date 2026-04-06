import SwiftUI
import AVKit

// MARK: - System Player (AVPlayerViewController wrapper)

struct SystemPlayerView: UIViewControllerRepresentable {
    let player: AVPlayer
    let subtitleEngine: SubtitleEngine
    var onChannelUp: () -> Void = {}
    var onChannelDown: () -> Void = {}

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let vc = AVPlayerViewController()
        vc.player = player
        vc.allowsPictureInPicturePlayback = false
        context.coordinator.setupSubtitleMenu(on: vc, engine: subtitleEngine)
        context.coordinator.setupSubtitleOverlay(on: vc, engine: subtitleEngine)

        // Swipe up/down for channel switching
        let swipeUp = UISwipeGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleSwipeUp))
        swipeUp.direction = .up
        let swipeDown = UISwipeGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleSwipeDown))
        swipeDown.direction = .down
        vc.view.addGestureRecognizer(swipeUp)
        vc.view.addGestureRecognizer(swipeDown)

        return vc
    }

    func updateUIViewController(_ vc: AVPlayerViewController, context: Context) {
        if vc.player !== player {
            vc.player = player
        }
        context.coordinator.onChannelUp = onChannelUp
        context.coordinator.onChannelDown = onChannelDown
        context.coordinator.setupSubtitleMenu(on: vc, engine: subtitleEngine)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onChannelUp: onChannelUp, onChannelDown: onChannelDown)
    }

    class Coordinator: NSObject {
        var onChannelUp: () -> Void
        var onChannelDown: () -> Void
        private var subtitleHosting: UIHostingController<SubtitleOverlayView>?

        init(onChannelUp: @escaping () -> Void, onChannelDown: @escaping () -> Void) {
            self.onChannelUp = onChannelUp
            self.onChannelDown = onChannelDown
        }

        @objc func handleSwipeUp() { onChannelUp() }
        @objc func handleSwipeDown() { onChannelDown() }

        func setupSubtitleOverlay(on vc: AVPlayerViewController, engine: SubtitleEngine) {
            guard subtitleHosting == nil, let overlay = vc.contentOverlayView else { return }
            let hosting = UIHostingController(rootView: SubtitleOverlayView(engine: engine))
            hosting.view.backgroundColor = .clear
            hosting.view.isUserInteractionEnabled = false
            hosting.view.translatesAutoresizingMaskIntoConstraints = false
            overlay.addSubview(hosting.view)
            NSLayoutConstraint.activate([
                hosting.view.leadingAnchor.constraint(equalTo: overlay.leadingAnchor),
                hosting.view.trailingAnchor.constraint(equalTo: overlay.trailingAnchor),
                hosting.view.topAnchor.constraint(equalTo: overlay.topAnchor),
                hosting.view.bottomAnchor.constraint(equalTo: overlay.bottomAnchor),
            ])
            subtitleHosting = hosting
        }

        @MainActor
        func setupSubtitleMenu(on vc: AVPlayerViewController, engine: SubtitleEngine) {
            let currentMode = engine.displayMode
            let actions = SubtitleDisplayMode.allCases.map { mode in
                UIAction(
                    title: mode.rawValue,
                    state: currentMode == mode ? .on : .off
                ) { _ in
                    Task { @MainActor in
                        engine.displayMode = mode
                    }
                }
            }

            let menu = UIMenu(title: "字幕", children: actions)
            vc.transportBarCustomMenuItems = [menu]
        }
    }
}

// MARK: - Subtitle Overlay

struct SubtitleOverlayView: View {
    @ObservedObject var engine: SubtitleEngine

    var body: some View {
        VStack {
            Spacer()

            if engine.displayMode != .off, hasText {
                VStack(spacing: 6) {
                    if showOriginal, !engine.currentOriginalText.isEmpty {
                        Text(engine.currentOriginalText)
                            .font(.system(size: 18))
                            .foregroundColor(Theme.textSecondary)
                    }
                    if showTranslation, !engine.currentTranslatedText.isEmpty {
                        Text(engine.currentTranslatedText)
                            .font(.system(size: 24, weight: .bold))
                            .foregroundColor(Theme.textPrimary)
                    }
                }
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)
                .padding(.vertical, 14)
                .background(Color.black.opacity(0.7))
                .cornerRadius(Theme.cornerRadius)
                .padding(.bottom, 120)
            }
        }
        .allowsHitTesting(false)
    }

    private var showOriginal: Bool {
        engine.displayMode == .originalOnly || engine.displayMode == .both
    }

    private var showTranslation: Bool {
        engine.displayMode == .translationOnly || engine.displayMode == .both
    }

    private var hasText: Bool {
        !engine.currentOriginalText.isEmpty || !engine.currentTranslatedText.isEmpty
    }
}

// MARK: - Channel Toast

struct ChannelToastView: View {
    let name: String
    let group: String

    var body: some View {
        VStack {
            HStack(spacing: 10) {
                Circle()
                    .fill(Theme.accent)
                    .frame(width: 10, height: 10)
                Text(name)
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundColor(Theme.textPrimary)
                if !group.isEmpty {
                    Text("·")
                        .foregroundColor(Theme.textSecondary)
                    Text(group)
                        .font(.subheadline)
                        .foregroundColor(Theme.textSecondary)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .background(Color.black.opacity(0.75))
            .cornerRadius(12)
            .padding(.top, 60)

            Spacer()
        }
    }
}

// MARK: - PlayerView

struct PlayerView: View {
    var channel: Channel?
    var allChannels: [Channel] = []

    @State private var player: AVPlayer?
    @State private var currentIndex: Int = 0
    @State private var currentChannelName: String = ""
    @State private var currentGroupTitle: String = ""
    @State private var showChannelToast: Bool = false
    @StateObject private var subtitleEngine = SubtitleEngine()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Theme.background
                .ignoresSafeArea()

            if let player = player {
                SystemPlayerView(
                    player: player,
                    subtitleEngine: subtitleEngine,
                    onChannelUp: { previousChannel() },
                    onChannelDown: { nextChannel() }
                )
                .ignoresSafeArea()

                if showChannelToast {
                    ChannelToastView(name: currentChannelName, group: currentGroupTitle)
                        .transition(.opacity)
                }
            } else {
                VStack(spacing: 20) {
                    Image(systemName: "play.tv")
                        .font(.system(size: 80))
                        .foregroundColor(Theme.textSecondary)
                    Text("选择频道开始观看")
                        .font(.title3)
                        .foregroundColor(Theme.textSecondary)
                }
            }
        }
        .onAppear { setupPlayer() }
        .onDisappear {
            player?.pause()
            player = nil
            subtitleEngine.stop()
        }
        .onChange(of: subtitleEngine.displayMode) { newMode in
            handleDisplayModeChange(newMode)
        }
    }

    // MARK: - Setup

    private func setupPlayer() {
        guard let channel = channel,
              let url = URL(string: channel.streamURL) else { return }

        currentChannelName = channel.name
        currentGroupTitle = channel.groupTitle
        if let idx = allChannels.firstIndex(where: { $0.id == channel.id }) {
            currentIndex = idx
        }

        let newPlayer = AVPlayer(url: url)
        self.player = newPlayer
        newPlayer.play()

        if subtitleEngine.displayMode != .off {
            subtitleEngine.start(streamURL: url)
        }
    }

    // MARK: - Channel Switching

    private func playChannel(at index: Int) {
        guard index >= 0, index < allChannels.count else { return }
        currentIndex = index
        let ch = allChannels[index]
        currentChannelName = ch.name
        currentGroupTitle = ch.groupTitle

        guard let url = URL(string: ch.streamURL) else { return }
        player?.replaceCurrentItem(with: AVPlayerItem(url: url))
        player?.play()

        subtitleEngine.stop()
        if subtitleEngine.displayMode != .off {
            subtitleEngine.start(streamURL: url)
        }

        showToast()
    }

    private func previousChannel() {
        guard !allChannels.isEmpty else { return }
        playChannel(at: currentIndex > 0 ? currentIndex - 1 : allChannels.count - 1)
    }

    private func nextChannel() {
        guard !allChannels.isEmpty else { return }
        playChannel(at: currentIndex < allChannels.count - 1 ? currentIndex + 1 : 0)
    }

    private func showToast() {
        withAnimation { showChannelToast = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            withAnimation { showChannelToast = false }
        }
    }

    private func handleDisplayModeChange(_ mode: SubtitleDisplayMode) {
        guard let ch = currentIndex < allChannels.count ? allChannels[currentIndex] : channel,
              let url = URL(string: ch.streamURL) else { return }

        if mode == .off {
            subtitleEngine.stop()
        } else if !subtitleEngine.isActive {
            subtitleEngine.start(streamURL: url)
        }
    }
}
