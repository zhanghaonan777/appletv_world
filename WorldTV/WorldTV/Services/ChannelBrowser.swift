import Foundation

/// Pure channel browsing logic: category lists, filtering, and sequential
/// (channel up/down) navigation with wraparound. No UI, no SwiftData context.
enum ChannelBrowser {

    static let allCategory = "全部频道"
    static let favoritesCategory = "收藏"
    static let recentCategory = "最近"

    /// Category list for the sidebar: special entries first, then sorted raw groups.
    static func categories(from channels: [Channel]) -> [String] {
        var result = [allCategory, favoritesCategory]
        if channels.contains(where: { $0.lastWatched != nil }) {
            result.append(recentCategory)
        }
        result.append(contentsOf: Set(channels.map { $0.groupTitle }).sorted())
        return result
    }

    /// Channels in a category, optionally narrowed by a case-insensitive name search.
    static func filter(_ channels: [Channel], category: String, search: String = "") -> [Channel] {
        var result: [Channel]
        switch category {
        case favoritesCategory:
            result = channels.filter { $0.isFavorite }
        case recentCategory:
            result = channels
                .filter { $0.lastWatched != nil }
                .sorted { ($0.lastWatched ?? .distantPast) > ($1.lastWatched ?? .distantPast) }
        case allCategory:
            result = channels
        default:
            result = channels.filter { $0.groupTitle == category }
        }
        if !search.isEmpty {
            let query = search.lowercased()
            result = result.filter { $0.name.lowercased().contains(query) }
        }
        return result
    }

    static func count(_ channels: [Channel], category: String) -> Int {
        filter(channels, category: category).count
    }

    /// Next channel after `current` in `list`, wrapping past the end.
    /// If `current` is not in `list`, returns the first channel.
    static func next(after current: Channel, in list: [Channel]) -> Channel? {
        guard !list.isEmpty else { return nil }
        guard let index = list.firstIndex(where: { $0.id == current.id }) else { return list.first }
        return list[(index + 1) % list.count]
    }

    /// Previous channel before `current` in `list`, wrapping past the start.
    /// If `current` is not in `list`, returns the last channel.
    static func previous(before current: Channel, in list: [Channel]) -> Channel? {
        guard !list.isEmpty else { return nil }
        guard let index = list.firstIndex(where: { $0.id == current.id }) else { return list.last }
        return list[(index - 1 + list.count) % list.count]
    }
}
