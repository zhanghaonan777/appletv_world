import Foundation
import SwiftData

@MainActor
final class PlaylistManager: ObservableObject {

    static let defaultPlaylistURL = "https://raw.githubusercontent.com/zhanghaonan777/appletv_world/main/playlist_lite.m3u"
    static let defaultPlaylistName = "World IPTV"

    private let modelContext: ModelContext

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

        errorMessage = nil

        do {
            let result = try await M3UParser.parse(from: remoteURL)

            // Upsert by stream URL — the channel's stable physical identity.
            // Existing Channel objects are updated in place, so favorites,
            // watch history, and any currently-playing reference all survive.
            let current = Array(playlist.channels)
            let existing = Dictionary(
                current.map { ($0.streamURL, $0) },
                uniquingKeysWith: { keep, _ in keep }
            )
            let parsedURLs = Set(result.channels.map { $0.streamURL })

            // Drop channels no longer in the playlist.
            for channel in current where !parsedURLs.contains(channel.streamURL) {
                modelContext.delete(channel)
            }

            // Update existing channels in place, insert new ones.
            for parsed in result.channels {
                if let channel = existing[parsed.streamURL] {
                    channel.name = parsed.name
                    channel.logoURL = parsed.logoURL
                    channel.groupTitle = parsed.groupTitle
                } else {
                    playlist.channels.append(Channel(
                        id: parsed.id,
                        name: parsed.name,
                        logoURL: parsed.logoURL,
                        groupTitle: parsed.groupTitle,
                        streamURL: parsed.streamURL
                    ))
                }
            }

            playlist.lastRefresh = Date()
            try modelContext.save()
        } catch {
            errorMessage = "Failed to refresh playlist: \(error.localizedDescription)"
        }
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
