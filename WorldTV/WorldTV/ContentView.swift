import SwiftUI

struct ContentView: View {
    @State private var selectedTab: Int = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            ChannelListView()
                .tabItem {
                    Label("频道", systemImage: "tv")
                }
                .tag(0)

            PlayerView()
                .tabItem {
                    Label("播放", systemImage: "play.rectangle")
                }
                .tag(1)

            SettingsView()
                .tabItem {
                    Label("设置", systemImage: "gearshape")
                }
                .tag(2)
        }
        .tint(Theme.accent)
    }
}
