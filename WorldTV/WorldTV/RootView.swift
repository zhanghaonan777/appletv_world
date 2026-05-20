import SwiftUI
import SwiftData

/// App root: a live-TV state machine. The player is the home screen; the mini
/// bar, full guide, and settings are overlays summoned over it.
struct RootView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var playlists: [Playlist]

    @State private var currentChannel: Channel?
    @State private var currentCategory: String = ChannelBrowser.allCategory
    @State private var overlay: Overlay = .fullGuide
    @State private var didDecideInitialState = false
    @StateObject private var playlistHolder = PlaylistManagerHolder()

    enum Overlay {
        case none, miniBar, fullGuide, settings
    }

    private var allChannels: [Channel] {
        playlists.flatMap { $0.channels }
    }

    /// Ordered channel list for the current category — drives channel up/down.
    private var categoryChannels: [Channel] {
        ChannelBrowser.filter(allChannels, category: currentCategory)
    }

    var body: some View {
        ZStack {
            Theme.background
                .ignoresSafeArea()

            if let channel = currentChannel {
                LivePlayerView(
                    channel: channel,
                    onChannelUp: { zap(-1) },
                    onChannelDown: { zap(1) },
                    onSelect: { overlay = .miniBar },
                    onExit: { overlay = .fullGuide }
                )
                .disabled(overlay != .none)
            }

            switch overlay {
            case .none:
                EmptyView()

            case .miniBar:
                if let channel = currentChannel {
                    MiniGuideBar(
                        channels: categoryChannels,
                        selectedChannel: Binding(
                            get: { channel },
                            set: { currentChannel = $0 }
                        ),
                        onExpand: { overlay = .fullGuide },
                        onDismiss: { overlay = .none }
                    )
                }

            case .fullGuide:
                ChannelGuideView(
                    allChannels: allChannels,
                    selectedCategory: $currentCategory,
                    onSelectChannel: { channel in
                        currentChannel = channel
                        overlay = .none
                    },
                    onOpenSettings: { overlay = .settings },
                    onDismiss: { if currentChannel != nil { overlay = .none } }
                )

            case .settings:
                SettingsView()
                    .onExitCommand { overlay = .fullGuide }
            }
        }
        .onAppear {
            playlistHolder.configure(modelContext: modelContext)
            Task { await playlistHolder.manager?.ensureDefaultPlaylist() }
        }
        .onChange(of: playlists.count) { _, _ in
            decideInitialStateIfNeeded()
        }
    }

    // MARK: - State

    /// Once channels are available, resume the last-watched channel or, on a
    /// fresh install, stay on the full guide so the user picks one.
    private func decideInitialStateIfNeeded() {
        guard !didDecideInitialState, !allChannels.isEmpty else { return }
        didDecideInitialState = true

        let lastWatched = allChannels
            .filter { $0.lastWatched != nil }
            .max { ($0.lastWatched ?? .distantPast) < ($1.lastWatched ?? .distantPast) }

        if let lastWatched {
            currentChannel = lastWatched
            currentCategory = lastWatched.groupTitle
            overlay = .none
        } else {
            overlay = .fullGuide
        }
    }

    private func zap(_ direction: Int) {
        guard let channel = currentChannel else { return }
        let list = categoryChannels
        let target = direction > 0
            ? ChannelBrowser.next(after: channel, in: list)
            : ChannelBrowser.previous(before: channel, in: list)
        if let target {
            currentChannel = target
            overlay = .miniBar
        }
    }
}

/// Creates a PlaylistManager lazily once a ModelContext is available.
@MainActor
final class PlaylistManagerHolder: ObservableObject {
    var manager: PlaylistManager?

    func configure(modelContext: ModelContext) {
        if manager == nil {
            manager = PlaylistManager(modelContext: modelContext)
        }
    }
}
