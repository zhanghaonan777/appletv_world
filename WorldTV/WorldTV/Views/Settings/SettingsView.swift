import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var playlists: [Playlist]

    @State private var showAddPlaylist = false
    @State private var newPlaylistName = ""
    @State private var newPlaylistURL = ""
    @State private var isRefreshing = false
    @State private var errorMessage: String?

    // Subtitle settings state
    @State private var realtimeSubtitlesEnabled = true
    @State private var displayMode = 0 // 0: 仅翻译, 1: 原文+翻译, 2: 仅原文
    @State private var subtitleSize = 1 // 0: Small, 1: Medium, 2: Large
    @State private var backgroundOpacity = 1 // 0: 低, 1: 中, 2: 高

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 40) {
                    // Playlist management
                    settingsSection(title: "播放列表管理", icon: "list.bullet") {
                        VStack(spacing: 16) {
                            ForEach(playlists) { playlist in
                                playlistRow(playlist)
                            }

                            if playlists.isEmpty {
                                Text("暂无播放列表")
                                    .foregroundColor(Theme.textSecondary)
                                    .frame(maxWidth: .infinity, alignment: .center)
                                    .padding()
                            }

                            Button {
                                newPlaylistName = ""
                                newPlaylistURL = PlaylistManager.defaultPlaylistURL
                                showAddPlaylist = true
                            } label: {
                                HStack {
                                    Image(systemName: "plus.circle.fill")
                                        .foregroundColor(Theme.accent)
                                    Text("添加播放列表")
                                        .foregroundColor(Theme.accent)
                                }
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding()
                                .background(Theme.card)
                                .cornerRadius(Theme.cornerRadius)
                                .overlay(
                                    RoundedRectangle(cornerRadius: Theme.cornerRadius)
                                        .stroke(Theme.border.opacity(0.3), lineWidth: 1)
                                )
                            }
                            .buttonStyle(.plain)

                            // Refresh all button
                            Button {
                                Task {
                                    isRefreshing = true
                                    let manager = PlaylistManager(modelContext: modelContext)
                                    await manager.refreshAllPlaylists()
                                    isRefreshing = false
                                }
                            } label: {
                                HStack {
                                    if isRefreshing {
                                        ProgressView()
                                            .tint(Theme.textPrimary)
                                    } else {
                                        Image(systemName: "arrow.clockwise")
                                    }
                                    Text(isRefreshing ? "刷新中..." : "刷新全部播放列表")
                                }
                                .foregroundColor(Theme.textPrimary)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding()
                                .background(Theme.secondary)
                                .cornerRadius(Theme.cornerRadius)
                            }
                            .buttonStyle(.plain)
                            .disabled(isRefreshing)
                        }
                    }

                    // Subtitle Settings
                    settingsSection(title: "字幕与翻译", icon: "captions.bubble") {
                        VStack(spacing: 12) {
                            // Real-time subtitles toggle
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("实时字幕")
                                        .foregroundColor(Theme.textPrimary)
                                    Text("自动识别并翻译字幕内容")
                                        .font(.caption)
                                        .foregroundColor(Theme.textSecondary)
                                }
                                Spacer()
                                Toggle("", isOn: $realtimeSubtitlesEnabled)
                                    .labelsHidden()
                                    .tint(Theme.accent)
                            }
                            .padding()
                            .background(Theme.card)
                            .cornerRadius(Theme.cornerRadius)

                            // Source language
                            infoRow(label: "源语言", value: "自动检测")
                            // Target language
                            infoRow(label: "目标语言", value: "中文")

                            // Display mode
                            VStack(alignment: .leading, spacing: 8) {
                                Text("显示模式")
                                    .foregroundColor(Theme.textSecondary)
                                    .padding(.horizontal)
                                HStack(spacing: 8) {
                                    ForEach(Array(["仅翻译", "原文+翻译", "仅原文"].enumerated()), id: \.offset) { index, title in
                                        Button {
                                            displayMode = index
                                        } label: {
                                            Text(title)
                                                .font(.caption)
                                                .foregroundColor(displayMode == index ? .white : Theme.textSecondary)
                                                .padding(.horizontal, 16)
                                                .padding(.vertical, 8)
                                                .background(displayMode == index ? Theme.accent : Theme.card)
                                                .cornerRadius(8)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .padding(.horizontal)
                            }
                            .padding(.vertical, 8)

                            // Subtitle size
                            VStack(alignment: .leading, spacing: 8) {
                                Text("字幕大小")
                                    .foregroundColor(Theme.textSecondary)
                                    .padding(.horizontal)
                                HStack(spacing: 8) {
                                    ForEach(Array(["小", "中", "大"].enumerated()), id: \.offset) { index, title in
                                        Button {
                                            subtitleSize = index
                                        } label: {
                                            Text(title)
                                                .font(.caption)
                                                .foregroundColor(subtitleSize == index ? .white : Theme.textSecondary)
                                                .padding(.horizontal, 16)
                                                .padding(.vertical, 8)
                                                .background(subtitleSize == index ? Theme.accent : Theme.card)
                                                .cornerRadius(8)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .padding(.horizontal)
                            }
                            .padding(.vertical, 8)

                            // Background opacity
                            VStack(alignment: .leading, spacing: 8) {
                                Text("背景透明度")
                                    .foregroundColor(Theme.textSecondary)
                                    .padding(.horizontal)
                                HStack(spacing: 8) {
                                    ForEach(Array(["低", "中", "高"].enumerated()), id: \.offset) { index, title in
                                        Button {
                                            backgroundOpacity = index
                                        } label: {
                                            Text(title)
                                                .font(.caption)
                                                .foregroundColor(backgroundOpacity == index ? .white : Theme.textSecondary)
                                                .padding(.horizontal, 16)
                                                .padding(.vertical, 8)
                                                .background(backgroundOpacity == index ? Theme.accent : Theme.card)
                                                .cornerRadius(8)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .padding(.horizontal)
                            }
                            .padding(.vertical, 8)
                        }
                    }

                    // Translation Model
                    settingsSection(title: "翻译模型", icon: "globe") {
                        VStack(spacing: 12) {
                            infoRow(label: "模型", value: "SMaLL-100")
                            infoRow(label: "模型大小", value: "300MB")
                            infoRow(label: "支持语言", value: "100种语言")
                            // Status with green indicator
                            HStack {
                                Text("状态")
                                    .foregroundColor(Theme.textSecondary)
                                Spacer()
                                HStack(spacing: 8) {
                                    Circle()
                                        .fill(Color.green)
                                        .frame(width: 8, height: 8)
                                    Text("已加载")
                                        .foregroundColor(.green)
                                }
                            }
                            .padding(.horizontal)
                            .padding(.vertical, 8)

                            // Progress bar showing loaded status
                            GeometryReader { geometry in
                                ZStack(alignment: .leading) {
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(Theme.card)
                                        .frame(height: 8)
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(Color.green)
                                        .frame(width: geometry.size.width, height: 8)
                                }
                            }
                            .frame(height: 8)
                            .padding(.horizontal)
                        }
                    }

                    // AI Features
                    settingsSection(title: "AI 功能", icon: "brain") {
                        VStack(spacing: 12) {
                            aiFeatureRow(title: "语音助手", icon: "lock.fill")
                            aiFeatureRow(title: "智能推荐", icon: "lock.fill")
                            aiFeatureRow(title: "内容总结", icon: "lock.fill")
                        }
                    }

                    // About
                    settingsSection(title: "关于", icon: "info.circle") {
                        VStack(spacing: 12) {
                            infoRow(label: "应用", value: "WorldTV")
                            infoRow(label: "版本", value: "1.0.0")
                            infoRow(label: "平台", value: "tvOS 17.0+")
                            infoRow(label: "已加载频道", value: "\(playlists.flatMap { $0.channels }.count)")
                        }
                    }

                    if let error = errorMessage {
                        Text(error)
                            .foregroundColor(Theme.destructive)
                            .font(.callout)
                            .padding()
                    }
                }
                .padding(60)
            }
            .background(Theme.background)
            .navigationTitle("设置")
            .alert("添加播放列表", isPresented: $showAddPlaylist) {
                TextField("播放列表名称", text: $newPlaylistName)
                TextField("M3U 地址", text: $newPlaylistURL)
                Button("添加") {
                    Task {
                        let name = newPlaylistName.isEmpty ? "我的播放列表" : newPlaylistName
                        let manager = PlaylistManager(modelContext: modelContext)
                        await manager.addPlaylist(name: name, url: newPlaylistURL)
                        errorMessage = manager.errorMessage
                    }
                }
                Button("取消", role: .cancel) { }
            } message: {
                Text("请输入播放列表名称和 M3U 地址")
            }
        }
    }

    // MARK: - Components

    @ViewBuilder
    private func settingsSection<Content: View>(title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .foregroundColor(Theme.accent)
                Text(title)
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundColor(Theme.textPrimary)
            }

            content()
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.primary)
        .cornerRadius(Theme.cardCornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardCornerRadius)
                .stroke(Theme.border.opacity(0.2), lineWidth: 1)
        )
    }

    private func playlistRow(_ playlist: Playlist) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(playlist.name)
                    .font(.body)
                    .foregroundColor(Theme.textPrimary)
                Text("\(playlist.channels.count) 个频道")
                    .font(.caption)
                    .foregroundColor(Theme.textSecondary)
                Text("更新于: \(playlist.lastRefresh.formatted(.dateTime.month().day().hour().minute()))")
                    .font(.caption2)
                    .foregroundColor(Theme.textSecondary.opacity(0.7))
            }

            Spacer()

            // Refresh single playlist
            Button {
                Task {
                    let manager = PlaylistManager(modelContext: modelContext)
                    await manager.refreshPlaylist(playlist)
                }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .foregroundColor(Theme.textSecondary)
            }
            .buttonStyle(.plain)

            // Delete playlist
            Button {
                let manager = PlaylistManager(modelContext: modelContext)
                manager.removePlaylist(playlist)
            } label: {
                Image(systemName: "trash")
                    .foregroundColor(Theme.destructive)
            }
            .buttonStyle(.plain)
        }
        .padding()
        .background(Theme.card)
        .cornerRadius(Theme.cornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cornerRadius)
                .stroke(Theme.border.opacity(0.3), lineWidth: 1)
        )
    }

    private func aiFeatureRow(title: String, icon: String) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .foregroundColor(Theme.textSecondary.opacity(0.5))
                Text("即将推出")
                    .font(.caption)
                    .foregroundColor(Theme.accent)
            }
            Spacer()
            Image(systemName: icon)
                .foregroundColor(Theme.textSecondary.opacity(0.3))
        }
        .padding()
        .background(Theme.card.opacity(0.5))
        .cornerRadius(Theme.cornerRadius)
    }

    private func infoRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .foregroundColor(Theme.textSecondary)
            Spacer()
            Text(value)
                .foregroundColor(Theme.textPrimary)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }
}
