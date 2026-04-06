import SwiftUI
import SwiftData

struct ChannelListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var playlists: [Playlist]

    @State private var selectedGroup: String = "全部频道"
    @State private var searchText: String = ""
    @State private var showFavoritesOnly: Bool = false
    @State private var selectedChannel: Channel?
    @State private var navigateToPlayer: Bool = false
    @State private var showSearch: Bool = false
    @StateObject private var playlistManager: PlaylistManagerHolder = PlaylistManagerHolder()

    private var allChannels: [Channel] {
        playlists.flatMap { $0.channels }
    }

    /// Map of display name to icon SF Symbol
    private var groupIconMap: [String: String] {
        [
            "全部频道": "rectangle.grid.2x2",
            "收藏": "star.fill",
            "最近": "clock",
            "央视": "tv",
            "卫视": "antenna.radiowaves.left.and.right",
            "地方": "map",
            "少儿": "figure.and.child.holdinghands",
            "体育": "sportscourt",
            "电影": "film",
            "新闻": "newspaper",
            "综艺": "music.mic",
            "纪录": "video",
            "教育": "book",
        ]
    }

    /// Raw group names from channel data
    private var rawGroups: [String] {
        let names = Set(allChannels.map { $0.groupTitle })
        return names.sorted()
    }

    /// Display groups with special entries first
    private var groups: [String] {
        let recentChannels = allChannels.filter { $0.lastWatched != nil }
        var result = ["全部频道", "收藏"]
        if !recentChannels.isEmpty {
            result.append("最近")
        }
        result += rawGroups
        return result
    }

    /// Count of channels in each group
    private func channelCount(for group: String) -> Int {
        switch group {
        case "全部频道":
            return allChannels.count
        case "收藏":
            return allChannels.filter { $0.isFavorite }.count
        case "最近":
            return allChannels.filter { $0.lastWatched != nil }.count
        default:
            return allChannels.filter { $0.groupTitle == group }.count
        }
    }

    private var filteredChannels: [Channel] {
        var result = allChannels

        switch selectedGroup {
        case "收藏":
            result = result.filter { $0.isFavorite }
        case "最近":
            result = result
                .filter { $0.lastWatched != nil }
                .sorted { ($0.lastWatched ?? .distantPast) > ($1.lastWatched ?? .distantPast) }
        case "全部频道":
            break
        default:
            result = result.filter { $0.groupTitle == selectedGroup }
        }

        if !searchText.isEmpty {
            let query = searchText.lowercased()
            result = result.filter { $0.name.lowercased().contains(query) }
        }

        return result
    }

    private let columns = [
        GridItem(.adaptive(minimum: 250, maximum: 350), spacing: 30)
    ]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Top header bar
                headerBar

                // Search bar (only shown when toggled)
                if showSearch {
                    HStack(spacing: 12) {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(Theme.textSecondary)
                        TextField("搜索频道...", text: $searchText)
                            .foregroundColor(Theme.textPrimary)
                        if !searchText.isEmpty {
                            Button {
                                searchText = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(Theme.textSecondary)
                            }
                            .buttonStyle(.plain)
                        }
                        Button {
                            searchText = ""
                            withAnimation { showSearch = false }
                        } label: {
                            Text("取消")
                                .foregroundColor(Theme.accent)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 40)
                    .padding(.vertical, 12)
                    .background(Theme.primary)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }

                HStack(spacing: 0) {
                    // Sidebar - group list
                    sidebarView

                    // Main content - channel grid
                    mainContentView
                }
            }
            .navigationDestination(for: Channel.self) { channel in
                PlayerView(channel: channel, allChannels: filteredChannels)
            }
            .onAppear {
                playlistManager.configure(modelContext: modelContext)
                Task {
                    await playlistManager.manager?.ensureDefaultPlaylist()
                }
            }
        }
    }

    // MARK: - Header Bar

    private var headerBar: some View {
        HStack {
            // WorldTV gradient logo
            Text("WorldTV")
                .font(.title3)
                .fontWeight(.bold)
                .foregroundStyle(
                    LinearGradient(
                        colors: [.white, Theme.accent],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )

            Spacer()

            HStack(spacing: 24) {
                Button {
                    withAnimation { showSearch.toggle() }
                } label: {
                    Image(systemName: "magnifyingglass")
                        .font(.title3)
                        .foregroundColor(showSearch ? Theme.accent : Theme.textSecondary)
                }
                .buttonStyle(.plain)

                NavigationLink(value: "settings") {
                    Image(systemName: "gearshape")
                        .font(.title3)
                        .foregroundColor(Theme.textSecondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 40)
        .padding(.vertical, 16)
        .background(Theme.primary)
    }

    // MARK: - Sidebar

    private var sidebarView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(groups, id: \.self) { group in
                    Button {
                        selectedGroup = group
                        showFavoritesOnly = (group == "收藏")
                    } label: {
                        HStack(spacing: 12) {
                            // Left accent border for selected group
                            if group == selectedGroup {
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(Theme.accent)
                                    .frame(width: 4, height: 28)
                            }

                            // Group icon
                            Image(systemName: groupIconMap[group] ?? "folder")
                                .font(.callout)
                                .foregroundColor(group == selectedGroup ? Theme.accent : Theme.textSecondary)
                                .frame(width: 24)

                            // Group name + count
                            Text(group)
                                .font(.callout)
                                .fontWeight(group == selectedGroup ? .semibold : .regular)
                                .foregroundColor(group == selectedGroup ? Theme.textPrimary : Theme.textSecondary)
                                .lineLimit(1)

                            Spacer()

                            Text("\(channelCount(for: group))")
                                .font(.caption)
                                .foregroundColor(Theme.textSecondary)
                                .fixedSize()
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(
                                    Capsule()
                                        .fill(Theme.muted)
                                )
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(group == selectedGroup ? Theme.secondary.opacity(0.4) : Color.clear)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding()
        }
        .frame(width: 380)
        .background(Theme.primary)
    }

    // MARK: - Main Content

    private var mainContentView: some View {
        VStack(spacing: 0) {
            // Header with count
            HStack {
                Text("\(filteredChannels.count) 个频道")
                    .font(.headline)
                    .foregroundColor(Theme.textSecondary)
                Spacer()
            }
            .padding(.horizontal, 40)
            .padding(.top, 20)

            if allChannels.isEmpty {
                Spacer()
                VStack(spacing: 20) {
                    Image(systemName: "tv.slash")
                        .font(.system(size: 60))
                        .foregroundColor(Theme.textSecondary)
                    Text("暂无频道")
                        .font(.title3)
                        .foregroundColor(Theme.textPrimary)
                    Text("请前往设置添加播放列表")
                        .font(.body)
                        .foregroundColor(Theme.textSecondary)
                }
                Spacer()
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 30) {
                        ForEach(filteredChannels) { channel in
                            NavigationLink(value: channel) {
                                ChannelCardView(channel: channel)
                            }
                            .buttonStyle(CardButtonStyle())
                        }
                    }
                    .padding(40)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .background(Theme.background)
    }
}

/// Wrapper to create PlaylistManager lazily once ModelContext is available.
@MainActor
final class PlaylistManagerHolder: ObservableObject {
    var manager: PlaylistManager?

    func configure(modelContext: ModelContext) {
        if manager == nil {
            manager = PlaylistManager(modelContext: modelContext)
        }
    }
}

/// Custom button style that adds focus scaling for tvOS cards.
struct CardButtonStyle: ButtonStyle {
    @Environment(\.isFocused) private var isFocused

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
    }
}
