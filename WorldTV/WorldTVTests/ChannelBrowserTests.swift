import XCTest
@testable import WorldTV

final class ChannelBrowserTests: XCTestCase {

    private func makeChannel(id: String, name: String, group: String,
                             favorite: Bool = false, watched: Date? = nil) -> Channel {
        let channel = Channel(id: id, name: name, logoURL: nil,
                              groupTitle: group, streamURL: "http://example.com/\(id)")
        channel.isFavorite = favorite
        channel.lastWatched = watched
        return channel
    }

    func testCategoriesSpecialEntriesFirstThenSortedGroups() {
        let channels = [
            makeChannel(id: "1", name: "A", group: "新闻"),
            makeChannel(id: "2", name: "B", group: "体育"),
        ]
        XCTAssertEqual(ChannelBrowser.categories(from: channels), ["全部频道", "收藏", "体育", "新闻"])
    }

    func testCategoriesIncludeRecentOnlyWhenSomethingWatched() {
        let noWatch = [makeChannel(id: "1", name: "A", group: "新闻")]
        XCTAssertFalse(ChannelBrowser.categories(from: noWatch).contains("最近"))

        let watched = [makeChannel(id: "1", name: "A", group: "新闻", watched: Date())]
        XCTAssertTrue(ChannelBrowser.categories(from: watched).contains("最近"))
    }

    func testFilterByGroup() {
        let channels = [
            makeChannel(id: "1", name: "A", group: "新闻"),
            makeChannel(id: "2", name: "B", group: "体育"),
        ]
        XCTAssertEqual(ChannelBrowser.filter(channels, category: "新闻").map(\.id), ["1"])
    }

    func testFilterFavorites() {
        let channels = [
            makeChannel(id: "1", name: "A", group: "新闻", favorite: true),
            makeChannel(id: "2", name: "B", group: "体育"),
        ]
        XCTAssertEqual(ChannelBrowser.filter(channels, category: "收藏").map(\.id), ["1"])
    }

    func testFilterRecentSortedByWatchedDescending() {
        let older = Date(timeIntervalSince1970: 1000)
        let newer = Date(timeIntervalSince1970: 2000)
        let channels = [
            makeChannel(id: "1", name: "A", group: "新闻", watched: older),
            makeChannel(id: "2", name: "B", group: "体育", watched: newer),
        ]
        XCTAssertEqual(ChannelBrowser.filter(channels, category: "最近").map(\.id), ["2", "1"])
    }

    func testFilterBySearchIsCaseInsensitive() {
        let channels = [
            makeChannel(id: "1", name: "CCTV News", group: "新闻"),
            makeChannel(id: "2", name: "Sports HD", group: "体育"),
        ]
        XCTAssertEqual(ChannelBrowser.filter(channels, category: "全部频道", search: "news").map(\.id), ["1"])
    }

    func testCount() {
        let channels = [
            makeChannel(id: "1", name: "A", group: "新闻"),
            makeChannel(id: "2", name: "B", group: "新闻"),
        ]
        XCTAssertEqual(ChannelBrowser.count(channels, category: "新闻"), 2)
        XCTAssertEqual(ChannelBrowser.count(channels, category: "体育"), 0)
    }

    func testNextWrapsAround() {
        let channels = [
            makeChannel(id: "1", name: "A", group: "x"),
            makeChannel(id: "2", name: "B", group: "x"),
        ]
        XCTAssertEqual(ChannelBrowser.next(after: channels[0], in: channels)?.id, "2")
        XCTAssertEqual(ChannelBrowser.next(after: channels[1], in: channels)?.id, "1")
    }

    func testPreviousWrapsAround() {
        let channels = [
            makeChannel(id: "1", name: "A", group: "x"),
            makeChannel(id: "2", name: "B", group: "x"),
        ]
        XCTAssertEqual(ChannelBrowser.previous(before: channels[0], in: channels)?.id, "2")
        XCTAssertEqual(ChannelBrowser.previous(before: channels[1], in: channels)?.id, "1")
    }

    func testNavigationWithChannelNotInListFallsBackToEdges() {
        let list = [makeChannel(id: "1", name: "A", group: "x")]
        let outsider = makeChannel(id: "99", name: "Z", group: "y")
        XCTAssertEqual(ChannelBrowser.next(after: outsider, in: list)?.id, "1")
        XCTAssertEqual(ChannelBrowser.previous(before: outsider, in: list)?.id, "1")
    }

    func testNavigationOnEmptyListReturnsNil() {
        let outsider = makeChannel(id: "99", name: "Z", group: "y")
        XCTAssertNil(ChannelBrowser.next(after: outsider, in: []))
        XCTAssertNil(ChannelBrowser.previous(before: outsider, in: []))
    }
}
