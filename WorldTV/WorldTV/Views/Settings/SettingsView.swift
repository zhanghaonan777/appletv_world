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

    @AppStorage("aiSubtitlesEnabled") private var aiSubtitlesEnabled = false

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

                    // AI subtitles (off by default — feature in development)
                    settingsSection(title: "AI 字幕", icon: "captions.bubble") {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("实时 AI 字幕")
                                    .foregroundColor(Theme.textPrimary)
                                Text("语音识别 + 翻译,功能开发中,默认关闭")
                                    .font(.caption)
                                    .foregroundColor(Theme.textSecondary)
                            }
                            Spacer()
                            Toggle("", isOn: $aiSubtitlesEnabled)
                                .labelsHidden()
                                .tint(Theme.accent)
                        }
                        .padding()
                        .background(Theme.card)
                        .cornerRadius(Theme.cornerRadius)
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
