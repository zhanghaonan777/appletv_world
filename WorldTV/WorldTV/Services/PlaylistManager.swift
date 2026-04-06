import Foundation
import SwiftData

@MainActor
final class PlaylistManager: ObservableObject {

    static let defaultPlaylistURL = "https://raw.githubusercontent.com/zhanghaonan777/appletv_world/main/playlist_lite.m3u"
    static let defaultPlaylistName = "World IPTV"

    private let modelContext: ModelContext

    @Published var isLoading = false
    @Published var errorMessage: String?

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // MARK: - Public API

    /// Add a new playlist by downloading and parsing its M3U URL.
    func addPlaylist(name: String, url: String) async {
        guard let remoteURL = URL(string: url) else {
            errorMessage = "Invalid URL: \(url)"
            return
        }

        isLoading = true
        errorMessage = nil

        do {
            let result = try await M3UParser.parse(from: remoteURL)

            let playlist = Playlist(name: name, url: url)

            for parsed in result.channels {
                let channel = Channel(
                    id: parsed.id,
                    name: parsed.name,
                    logoURL: parsed.logoURL,
                    groupTitle: parsed.groupTitle,
                    streamURL: parsed.streamURL
                )
                playlist.channels.append(channel)
            }

            modelContext.insert(playlist)
            try modelContext.save()
        } catch {
            errorMessage = "Failed to load playlist: \(error.localizedDescription)"
        }

        isLoading = false
    }

    /// Remove a playlist by its persistent model ID.
    func removePlaylist(_ playlist: Playlist) {
        modelContext.delete(playlist)
        try? modelContext.save()
    }

    /// Re-download and re-parse a single playlist.
    func refreshPlaylist(_ playlist: Playlist) async {
        guard let remoteURL = URL(string: playlist.url) else {
            errorMessage = "Invalid URL: \(playlist.url)"
            return
        }

        isLoading = true
        errorMessage = nil

        do {
            let result = try await M3UParser.parse(from: remoteURL)

            // Preserve favorite status
            let favoriteIds = Set(playlist.channels.filter { $0.isFavorite }.map { $0.id })

            // Remove old channels
            for channel in playlist.channels {
                modelContext.delete(channel)
            }
            playlist.channels.removeAll()

            // Insert new channels
            for parsed in result.channels {
                let channel = Channel(
                    id: parsed.id,
                    name: parsed.name,
                    logoURL: parsed.logoURL,
                    groupTitle: parsed.groupTitle,
                    streamURL: parsed.streamURL
                )
                channel.isFavorite = favoriteIds.contains(parsed.id)
                playlist.channels.append(channel)
            }

            playlist.lastRefresh = Date()
            try modelContext.save()
        } catch {
            errorMessage = "Failed to refresh playlist: \(error.localizedDescription)"
        }

        isLoading = false
    }

    /// Refresh all playlists.
    func refreshAllPlaylists() async {
        let descriptor = FetchDescriptor<Playlist>()
        guard let playlists = try? modelContext.fetch(descriptor) else { return }
        for playlist in playlists {
            await refreshPlaylist(playlist)
        }
    }

    /// Ensure the default playlist exists; if no playlists are present, add the default one.
    func ensureDefaultPlaylist() async {
        let descriptor = FetchDescriptor<Playlist>()
        let count = (try? modelContext.fetchCount(descriptor)) ?? 0
        if count == 0 {
            await addPlaylist(name: Self.defaultPlaylistName, url: Self.defaultPlaylistURL)
        }
    }
}
