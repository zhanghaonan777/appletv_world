import XCTest
@testable import WorldTV

final class WorldTVTests: XCTestCase {

    func testM3UParserBasic() {
        let content = """
        #EXTM3U x-tvg-url="http://example.com/epg.xml"
        #EXTINF:-1 tvg-id="ch1" tvg-name="Test Channel" tvg-logo="http://example.com/logo.png" group-title="News",Test Channel
        http://example.com/stream.m3u8
        #EXTINF:-1 tvg-id="ch2" tvg-name="Sports Channel" group-title="Sports",Sports Channel
        http://example.com/sports.m3u8
        """

        let result = M3UParser.parse(content: content)

        XCTAssertEqual(result.channels.count, 2)
        XCTAssertEqual(result.epgURL, "http://example.com/epg.xml")

        XCTAssertEqual(result.channels[0].name, "Test Channel")
        XCTAssertEqual(result.channels[0].groupTitle, "News")
        XCTAssertEqual(result.channels[0].logoURL, "http://example.com/logo.png")
        XCTAssertEqual(result.channels[0].streamURL, "http://example.com/stream.m3u8")

        XCTAssertEqual(result.channels[1].name, "Sports Channel")
        XCTAssertEqual(result.channels[1].groupTitle, "Sports")
    }

    func testM3UParserMalformedLines() {
        let content = """
        #EXTM3U
        #EXTINF:-1 group-title="Test",Good Channel
        http://example.com/good.m3u8
        This is not a valid line
        #EXTINF:-1 group-title="Test",Another Channel
        not-a-url
        #EXTINF:-1 group-title="Test",Valid Channel
        https://example.com/valid.m3u8
        """

        let result = M3UParser.parse(content: content)
        XCTAssertEqual(result.channels.count, 2)
        XCTAssertEqual(result.channels[0].name, "Good Channel")
        XCTAssertEqual(result.channels[1].name, "Valid Channel")
    }

    func testM3UParserEmptyContent() {
        let result = M3UParser.parse(content: "")
        XCTAssertTrue(result.channels.isEmpty)
        XCTAssertNil(result.epgURL)
    }

    func testM3UParserUncategorized() {
        let content = """
        #EXTM3U
        #EXTINF:-1,No Group Channel
        http://example.com/stream.m3u8
        """

        let result = M3UParser.parse(content: content)
        XCTAssertEqual(result.channels.count, 1)
        XCTAssertEqual(result.channels[0].groupTitle, "Uncategorized")
    }
}
