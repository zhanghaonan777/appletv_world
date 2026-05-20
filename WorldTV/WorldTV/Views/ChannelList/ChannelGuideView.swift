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

    private let columns = [GridItem(.adaptive(minimum: 260, maximum: 360), spacing: 36)]

    private let groupIconMap: [String: String] = [
        "全部频道": "square.grid.2x2.fill",
        "收藏": "star.fill",
        "最近": "clock.fill",
        "央视": "tv.fill",
        "卫视": "antenna.radiowaves.left.and.right",
        "地方": "map.fill",
        "少儿": "figure.and.child.holdinghands",
        "体育": "sportscourt.fill",
        "电影": "film.fill",
        "新闻": "newspaper.fill",
        "综艺": "music.mic",
        "纪录": "video.fill",
        "教育": "book.fill",
    ]

    private var categories: [String] {
        ChannelBrowser.categories(from: allChannels)
    }

    private var filteredChannels: [Channel] {
        ChannelBrowser.filter(allChannels, category: selectedCategory, search: searchText)
    }

    var body: some View {
        ZStack {
            Theme.backdrop

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
        HStack(alignment: .center) {
            HStack(spacing: 0) {
                Text("World")
                    .foregroundStyle(Theme.textPrimary)
                Text("TV")
                    .foregroundStyle(Theme.accentGradient)
            }
            .font(.system(size: 46, weight: .black))
            .tracking(0.5)

            Spacer()

            HStack(spacing: 28) {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { showSearch.toggle() }
                } label: {
                    IconBadge(systemName: "magnifyingglass", highlighted: showSearch)
                }
                .buttonStyle(GuidePlainButtonStyle())

                Button {
                    onOpenSettings()
                } label: {
                    IconBadge(systemName: "gearshape.fill", highlighted: false)
                }
                .buttonStyle(GuidePlainButtonStyle())
            }
        }
        .padding(.horizontal, 56)
        .padding(.top, 32)
        .padding(.bottom, 24)
    }

    private var searchBar: some View {
        HStack(spacing: 14) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 22, weight: .semibold))
                .foregroundColor(Theme.textSecondary)
            TextField("搜索频道", text: $searchText)
                .font(.system(size: 24))
                .foregroundColor(Theme.textPrimary)
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(Theme.textSecondary)
                }
                .buttonStyle(GuidePlainButtonStyle())
            }
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 18)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.06))
        )
        .padding(.horizontal, 56)
        .padding(.bottom, 16)
    }

    // MARK: - Sidebar

    private var sidebarView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(categories, id: \.self) { category in
                    Button {
                        selectedCategory = category
                    } label: {
                        CategoryRow(
                            title: category,
                            icon: groupIconMap[category] ?? "folder.fill",
                            count: ChannelBrowser.count(allChannels, category: category),
                            isSelected: category == selectedCategory
                        )
                    }
                    .buttonStyle(GuidePlainButtonStyle())
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
        }
        .frame(width: 440)
        .background(
            LinearGradient(
                colors: [Color.white.opacity(0.05), Color.white.opacity(0.01)],
                startPoint: .top, endPoint: .bottom
            )
        )
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(width: 1)
        }
    }

    // MARK: - Channel Grid

    private var mainContentView: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Text("\(filteredChannels.count)")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(Theme.accentGradient)
                    .monospacedDigit()
                Text("个频道")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundColor(Theme.textSecondary)
                Spacer()
            }
            .padding(.horizontal, 48)
            .padding(.top, 24)

            if allChannels.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 36) {
                        ForEach(filteredChannels) { channel in
                            Button {
                                onSelectChannel(channel)
                            } label: {
                                ChannelCardView(channel: channel)
                            }
                            .buttonStyle(CardButtonStyle())
                        }
                    }
                    .padding(48)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "tv.slash")
                .font(.system(size: 72))
                .foregroundColor(Theme.textSecondary)
            Text("暂无频道")
                .font(.system(size: 28, weight: .semibold))
                .foregroundColor(Theme.textPrimary)
            Text("请前往设置添加播放列表")
                .font(.system(size: 20))
                .foregroundColor(Theme.textSecondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Sidebar Category Row

private struct CategoryRow: View {
    let title: String
    let icon: String
    let count: Int
    let isSelected: Bool
    @Environment(\.isFocused) private var isFocused

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .semibold))
                .frame(width: 32)

            Text(title)
                .font(.system(size: 26, weight: isSelected ? .bold : .medium))
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            Spacer(minLength: 8)

            Text("\(count)")
                .font(.system(size: 18, weight: .semibold))
                .monospacedDigit()
                .foregroundColor(isSelected ? .white : Theme.textSecondary)
                .padding(.horizontal, 11)
                .padding(.vertical, 4)
                .background(
                    Capsule().fill(isSelected ? Color.white.opacity(0.22) : Color.white.opacity(0.07))
                )
        }
        .foregroundStyle(textColor)
        .padding(.horizontal, 20)
        .padding(.vertical, 15)
        .background(
            RoundedRectangle(cornerRadius: 14).fill(fillStyle)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(focusStroke, lineWidth: 2)
        )
        .shadow(color: isSelected ? Theme.accent.opacity(0.45) : .clear,
                radius: isSelected ? 14 : 0, y: 4)
        .scaleEffect(isFocused ? 1.04 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.72), value: isFocused)
    }

    private var textColor: Color {
        if isSelected { return .white }
        return isFocused ? Theme.textPrimary : Theme.textSecondary
    }

    private var fillStyle: AnyShapeStyle {
        if isSelected { return AnyShapeStyle(Theme.accentGradient) }
        if isFocused { return AnyShapeStyle(Color.white.opacity(0.10)) }
        return AnyShapeStyle(Color.clear)
    }

    private var focusStroke: Color {
        guard isFocused else { return .clear }
        return isSelected ? Color.white.opacity(0.7) : Theme.accent
    }
}

// MARK: - Header Icon

private struct IconBadge: View {
    let systemName: String
    let highlighted: Bool
    @Environment(\.isFocused) private var isFocused

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 24, weight: .semibold))
            .foregroundColor(highlighted || isFocused ? .white : Theme.textSecondary)
            .frame(width: 60, height: 60)
            .background(
                Circle().fill(
                    isFocused ? AnyShapeStyle(Theme.accentGradient)
                              : AnyShapeStyle(Color.white.opacity(highlighted ? 0.14 : 0.06))
                )
            )
            .scaleEffect(isFocused ? 1.12 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.72), value: isFocused)
    }
}

// MARK: - Button Styles

/// Suppresses the default tvOS focus pill; focus visuals live in the label
/// via `@Environment(\.isFocused)`.
struct GuidePlainButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.7 : 1.0)
    }
}

/// Focus scaling for tvOS channel cards.
struct CardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
    }
}
