import Foundation
import SwiftData

@Model
class Playlist: Identifiable {
    @Attribute(.unique) var id: UUID
    var name: String
    var url: String
    var lastRefresh: Date
    @Relationship(deleteRule: .cascade) var channels: [Channel]

    init(name: String, url: String) {
        self.id = UUID()
        self.name = name
        self.url = url
        self.lastRefresh = Date()
        self.channels = []
    }
}

@Model
class Channel: Identifiable {
    @Attribute(.unique) var id: String
    var name: String
    var logoURL: String?
    var groupTitle: String
    var streamURL: String
    var isFavorite: Bool
    var lastWatched: Date?

    init(id: String, name: String, logoURL: String?, groupTitle: String, streamURL: String) {
        self.id = id
        self.name = name
        self.logoURL = logoURL
        self.groupTitle = groupTitle
        self.streamURL = streamURL
        self.isFavorite = false
        self.lastWatched = nil
    }
}
