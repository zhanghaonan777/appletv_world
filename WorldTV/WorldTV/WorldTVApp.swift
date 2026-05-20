import SwiftUI
import SwiftData

@main
struct WorldTVApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(for: [Playlist.self, Channel.self])
    }
}
