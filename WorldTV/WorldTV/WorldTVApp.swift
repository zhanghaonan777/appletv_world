import SwiftUI
import SwiftData

@main
struct WorldTVApp: App {
    init() {
        // Larger cache so channel logos aren't re-downloaded on every scroll.
        URLCache.shared = URLCache(memoryCapacity: 32 * 1024 * 1024,
                                   diskCapacity: 256 * 1024 * 1024)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(for: [Playlist.self, Channel.self])
    }
}
