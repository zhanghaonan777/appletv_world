import SwiftUI

/// Fullscreen channel guide shown as an overlay over the playing video:
/// category sidebar + channel grid + search + a settings entry.
struct ChannelGuideView: View {
    let allChannels: [Channel]
    @Binding var selectedCategory: String
    var onSelectChannel: (Channel) -> Void = { _ in }
    var onOpenSettings: () -> Void = {}
    var onDismiss: () -> Void = {}

    @State private var searchText: String = ""
    @State private var showSearch: Bool = false

    private let columns = [GridItem(.adaptive(minimum: 250, maximum: 350), spacing: 30)]

    private let groupIconMap: [String: String] = [
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

    private var categories: [String] {
        ChannelBrowser.categories(from: allChannels)
    }

    private var filteredChannels: [Channel] {
        ChannelBrowser.filter(allChannels, category: selectedCategory, search: searchText)
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.92)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                headerBar

                if showSearch {
                    searchBar
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                HStack(spacing: 0) {
                    sidebarView
                    mainContentView
                }
            }
        }
        .onExitCommand { onDismiss() }
    }

    // MARK: - Header

    private var headerBar: some View {
        HStack {
            Text("WorldTV")
                .font(.title3)
                .fontWeight(.bold)
                .foregroundStyle(
                    LinearGradient(colors: [.white, Theme.accent],
                                   startPoint: .leading, endPoint: .trailing)
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

                Button {
                    onOpenSettings()
                } label: {
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

    private var searchBar: some View {
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
        }
        .padding(.horizontal, 40)
        .padding(.vertical, 12)
        .background(Theme.primary)
    }

    // MARK: - Sidebar

    private var sidebarView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(categories, id: \.self) { category in
                    Button {
                        selectedCategory = category
                    } label: {
                        HStack(spacing: 12) {
                            if category == selectedCategory {
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(Theme.accent)
                                    .frame(width: 4, height: 28)
                            }

                            Image(systemName: groupIconMap[category] ?? "folder")
                                .font(.callout)
                                .foregroundColor(category == selectedCategory ? Theme.accent : Theme.textSecondary)
                                .frame(width: 24)

                            Text(category)
                                .font(.callout)
                                .fontWeight(category == selectedCategory ? .semibold : .regular)
                                .foregroundColor(category == selectedCategory ? Theme.textPrimary : Theme.textSecondary)
                                .lineLimit(1)

                            Spacer()

                            Text("\(ChannelBrowser.count(allChannels, category: category))")
                                .font(.caption)
                                .foregroundColor(Theme.textSecondary)
                                .fixedSize()
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Theme.muted))
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(category == selectedCategory ? Theme.secondary.opacity(0.4) : Color.clear)
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

    // MARK: - Channel Grid

    private var mainContentView: some View {
        VStack(spacing: 0) {
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
                            Button {
                                onSelectChannel(channel)
                            } label: {
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
    }
}

/// Focus scaling for tvOS channel cards.
struct CardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
    }
}
