import SwiftUI
import SwiftData

/// App root. Owns the single `AppModel` and a single `@FocusState`; every
/// child view renders from the model and forwards remote input to it.
struct RootView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var playlists: [Playlist]

    @State private var appModel = AppModel()
    @State private var didBootstrap = false
    @StateObject private var playlistHolder = PlaylistManagerHolder()
    @FocusState private var focus: FocusZone?

    private var allChannels: [Channel] {
        playlists.flatMap { $0.channels }
    }

    var body: some View {
        ZStack {
            Theme.background
                .ignoresSafeArea()

            if appModel.currentChannel != nil {
                LivePlayerView(appModel: appModel, channels: allChannels)
                    .focused($focus, equals: .player)
                    .disabled(appModel.focusZone != .player)
            }

            switch appModel.screen {
            case .player:
                EmptyView()

            case .miniBar:
                if appModel.currentChannel != nil {
                    MiniGuideBar(appModel: appModel, channels: allChannels)
                        .focused($focus, equals: .miniBar)
                }

            case .guide:
                ChannelGuideView(appModel: appModel, channels: allChannels)
                    .focused($focus, equals: .guide)

            case .settings:
                SettingsView()
                    .focused($focus, equals: .settings)
                    .onExitCommand { appModel.handle(.menu, channels: allChannels) }
            }
        }
        .onAppear {
            playlistHolder.configure(modelContext: modelContext)
            Task { await playlistHolder.manager?.ensureDefaultPlaylist() }
            bootstrapIfNeeded()
            focus = appModel.focusZone
        }
        .onChange(of: playlists.count) { _, _ in
            bootstrapIfNeeded()
        }
        .onChange(of: appModel.focusZone) { _, zone in
            focus = zone
        }
    }

    /// Decide the initial screen once channels are available (warm launches
    /// load synchronously, so `.onChange` may never fire — also called here).
    private func bootstrapIfNeeded() {
        guard !didBootstrap, !allChannels.isEmpty else { return }
        didBootstrap = true
        appModel.bootstrap(channels: allChannels)
        focus = appModel.focusZone
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
