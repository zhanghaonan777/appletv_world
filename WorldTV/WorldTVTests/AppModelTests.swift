import XCTest
@testable import WorldTV

/// Covers the interaction success criteria (scenarios a–h) of the
/// interaction-core refactor goal.
final class AppModelTests: XCTestCase {

    private func makeChannel(_ id: String, group: String, watched: Date? = nil) -> Channel {
        let channel = Channel(id: id, name: "Channel \(id)", logoURL: nil,
                              groupTitle: group, streamURL: "http://example.com/\(id)")
        channel.lastWatched = watched
        return channel
    }

    /// "新闻": n1 n2 n3   "体育": s1 s2
    private func sampleChannels() -> [Channel] {
        [makeChannel("n1", group: "新闻"),
         makeChannel("n2", group: "新闻"),
         makeChannel("n3", group: "新闻"),
         makeChannel("s1", group: "体育"),
         makeChannel("s2", group: "体育")]
    }

    // a. player up/down switches channel, never opens the guide or exits
    func testPlayerUpDownSwitchesChannelAndStaysInPlayer() {
        let channels = sampleChannels()
        let model = AppModel(screen: .player, currentChannel: channels[1], currentCategory: "新闻")

        model.handle(.up, channels: channels)
        XCTAssertEqual(model.currentChannel?.id, "n1")
        XCTAssertEqual(model.screen, .player)

        model.handle(.down, channels: channels)
        model.handle(.down, channels: channels)
        XCTAssertEqual(model.currentChannel?.id, "n3")
        XCTAssertEqual(model.screen, .player)
    }

    // b. player select / left / right opens the mini bar
    func testPlayerSelectAndArrowsOpenMiniBar() {
        let channels = sampleChannels()
        for button in [RemoteButton.select, .left, .right] {
            let model = AppModel(screen: .player, currentChannel: channels[0], currentCategory: "新闻")
            model.handle(button, channels: channels)
            XCTAssertEqual(model.screen, .miniBar(.channels))
        }
    }

    // c. player menu opens the full guide
    func testPlayerMenuOpensGuide() {
        let channels = sampleChannels()
        let model = AppModel(screen: .player, currentChannel: channels[0], currentCategory: "新闻")
        model.handle(.menu, channels: channels)
        XCTAssertEqual(model.screen, .guide)
    }

    // d. mini bar up/down switches rows, left/right moves within a row,
    //    switching category syncs the channel
    func testMiniBarRowSwitchingAndMovement() {
        let channels = sampleChannels()
        // categories sort to ["全部频道", "收藏", "体育", "新闻"]; start in 体育/s1.
        let model = AppModel(screen: .miniBar(.channels), currentChannel: channels[3], currentCategory: "体育")

        model.handle(.right, channels: channels)        // channels row: s1 -> s2
        XCTAssertEqual(model.currentChannel?.id, "s2")

        model.handle(.up, channels: channels)
        XCTAssertEqual(model.screen, .miniBar(.categories))

        model.handle(.right, channels: channels)        // categories row: 体育 -> 新闻
        XCTAssertEqual(model.currentCategory, "新闻")
        XCTAssertEqual(model.currentChannel?.id, "n1", "switching category should sync the channel")

        model.handle(.down, channels: channels)
        XCTAssertEqual(model.screen, .miniBar(.channels))
    }

    // e. mini bar select opens the guide; menu returns to the player
    func testMiniBarSelectOpensGuideAndMenuReturnsToPlayer() {
        let channels = sampleChannels()

        let toGuide = AppModel(screen: .miniBar(.channels), currentChannel: channels[0], currentCategory: "新闻")
        toGuide.handle(.select, channels: channels)
        XCTAssertEqual(toGuide.screen, .guide)

        let toPlayer = AppModel(screen: .miniBar(.categories), currentChannel: channels[0], currentCategory: "新闻")
        toPlayer.handle(.menu, channels: channels)
        XCTAssertEqual(toPlayer.screen, .player)
    }

    // f. guide: picking a channel returns to the player; menu returns to the player
    func testGuideSelectChannelAndMenuReturnToPlayer() {
        let channels = sampleChannels()

        let pick = AppModel(screen: .guide, currentChannel: channels[0], currentCategory: "新闻")
        pick.selectChannelFromGuide(channels[3])
        XCTAssertEqual(pick.currentChannel?.id, "s1")
        XCTAssertEqual(pick.currentCategory, "体育")
        XCTAssertEqual(pick.screen, .player)

        let menu = AppModel(screen: .guide, currentChannel: channels[0], currentCategory: "新闻")
        menu.handle(.menu, channels: channels)
        XCTAssertEqual(menu.screen, .player)
    }

    // g. focus zone is correct after opening/closing overlays
    func testFocusZoneIsCorrectAcrossTransitions() {
        let channels = sampleChannels()
        let model = AppModel(screen: .player, currentChannel: channels[0], currentCategory: "新闻")
        XCTAssertEqual(model.focusZone, .player)

        model.handle(.menu, channels: channels)        // -> guide
        XCTAssertEqual(model.focusZone, .guide)

        model.handle(.menu, channels: channels)        // -> player
        XCTAssertEqual(model.focusZone, .player)

        model.handle(.select, channels: channels)      // -> mini bar
        XCTAssertEqual(model.focusZone, .miniBar)

        model.handle(.menu, channels: channels)        // -> player
        XCTAssertEqual(model.focusZone, .player)
    }

    // h. video is covered only by the guide/settings, not the player/mini bar
    func testVideoCoveredOnlyForFullscreenOverlays() {
        let channels = sampleChannels()
        let model = AppModel(screen: .player, currentChannel: channels[0], currentCategory: "新闻")
        XCTAssertFalse(model.isVideoCovered)

        model.screen = .miniBar(.channels)
        XCTAssertFalse(model.isVideoCovered)

        model.screen = .guide
        XCTAssertTrue(model.isVideoCovered)

        model.screen = .settings
        XCTAssertTrue(model.isVideoCovered)
    }
}
