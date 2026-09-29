import XCTest
@testable import AIPulseCore

final class FeedParsingTests: XCTestCase {
    func testParsesRSS20() {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <rss version="2.0"><channel>
            <title>OpenAI News</title>
            <item>
                <title>GPT-5 announced</title>
                <link>https://openai.com/blog/gpt5</link>
                <description>Our new frontier model.</description>
                <pubDate>Mon, 28 Sep 2026 10:00:00 GMT</pubDate>
                <guid>https://openai.com/blog/gpt5</guid>
            </item>
            <item>
                <title>DevDay recap</title>
                <link>https://openai.com/blog/devday</link>
                <description>Summary of talks.</description>
                <pubDate>Tue, 29 Sep 2026 08:30:00 GMT</pubDate>
            </item>
        </channel></rss>
        """
        let items = FeedParsing.parse(data: Data(xml.utf8), source: .openai)
        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(items[0].title, "GPT-5 announced")
        XCTAssertEqual(items[0].url.absoluteString, "https://openai.com/blog/gpt5")
        XCTAssertEqual(items[0].publishedAt, Date(timeIntervalSince1970: 1_790_589_600))
        XCTAssertNil(items[0].engagement, "RSS items carry no engagement — unknown, not zero")
        XCTAssertEqual(items[1].publishedAt, Date(timeIntervalSince1970: 1_790_670_600))
    }

    func testParsesAtom() {
        let xml = """
        <?xml version="1.0" encoding="utf-8"?>
        <feed xmlns="http://www.w3.org/2005/Atom">
            <title>Simon Willison</title>
            <entry>
                <title>Notes on LLM tooling</title>
                <link href="https://simonwillison.net/2026/Sep/29/llm-tooling/"/>
                <summary>New developer tools for local models.</summary>
                <published>2026-09-29T12:00:00Z</published>
            </entry>
        </feed>
        """
        let items = FeedParsing.parse(data: Data(xml.utf8), source: .simonwillison)
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].title, "Notes on LLM tooling")
        XCTAssertEqual(items[0].url.absoluteString, "https://simonwillison.net/2026/Sep/29/llm-tooling/")
        XCTAssertEqual(items[0].summary, "New developer tools for local models.")
        XCTAssertEqual(items[0].publishedAt, Date(timeIntervalSince1970: 1_790_683_200))
    }

    func testParsesAlgoliaJSON() {
        let json = """
        {"hits":[
          {"objectID":"a1","title":"LLM inference engine released","url":"https://github.com/x/y",
           "points":320,"num_comments":45,"created_at_i":1790553600},
          {"objectID":"a2","title":null,"storyTitle":"Fallback title","url":null,
           "storyURL":"https://example.com/s","created_at":"2026-09-28T00:00:00Z"}
        ]}
        """
        let items = FeedParsing.parse(data: Data(json.utf8), source: .hackerNews)
        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(items[0].id, "a1")
        XCTAssertEqual(items[0].engagement?.points, 320)
        XCTAssertEqual(items[0].engagement?.comments, 45)
        XCTAssertEqual(items[0].publishedAt, Date(timeIntervalSince1970: 1_790_553_600))
        XCTAssertEqual(items[1].title, "Fallback title")
        XCTAssertEqual(items[1].url.absoluteString, "https://example.com/s")
    }

    func testMalformedXMLSkipsNotCrashes() {
        let xml = """
        <rss version="2.0"><channel>
            <item><title>Good item</title><link>https://a.example/1</link></item>
            <item><title>Broken & unescaped < tag</link></item>
            <item><title></title><link>https://a.example/2</link></item>
        </channel></rss>
        """
        let items = FeedParsing.parse(data: Data(xml.utf8), source: .openai)
        XCTAssertEqual(items.count, 1, "only the well-formed item survives")
        XCTAssertEqual(items[0].title, "Good item")
    }

    func testItemWithoutLinkIsSkipped() {
        let entry: [String: String] = ["title": "No link here"]
        XCTAssertNil(FeedParsing.item(fromEntry: entry, source: .openai, fetchedAt: .now))
    }

    func testDateVariants() {
        XCTAssertNotNil(FeedParsing.parseXMLDate("Mon, 29 Sep 2026 10:00:00 GMT"))
        XCTAssertNotNil(FeedParsing.parseXMLDate("29 Sep 2026 10:00:00 GMT"))
        XCTAssertNotNil(FeedParsing.parseXMLDate("2026-09-29T10:00:00Z"))
        XCTAssertNotNil(FeedParsing.parseXMLDate("2026-09-29T10:00:00.500Z"))
        XCTAssertNil(FeedParsing.parseXMLDate("not a date"))
        XCTAssertNil(FeedParsing.parseXMLDate(nil))
        XCTAssertNil(FeedParsing.parseXMLDate(""))
    }

    func testRedditRSSParse() {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <feed xmlns="http://www.w3.org/2005/Atom">
            <entry>
                <title>A new local LLM runs on CPU</title>
                <link href="https://www.reddit.com/r/LocalLLaMA/comments/abc/"/>
                <updated>2026-09-29T09:00:00Z</updated>
            </entry>
        </feed>
        """
        let items = FeedParsing.parse(data: Data(xml.utf8), source: .redditLocalLLaMA)
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].source, .redditLocalLLaMA)
        XCTAssertEqual(items[0].publishedAt, Date(timeIntervalSince1970: 1_790_672_400))
    }

    func testCDATAContentIsCaptured() {
        // Pins CDATA handling: CDATA-wrapped titles/descriptions (WordPress-
        // style feeds) must flow into entries. foundCDATA is implemented as
        // a defensive callback, but on this toolchain XMLParser already
        // routes CDATA through foundCharacters when the delegate implements
        // only foundCharacters — verified against old code (test passed both
        // ways), so this is a behavior pin, not a regression.
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <rss version="2.0"><channel>
            <item>
                <title><![CDATA[New open-source LLM toolkit]]></title>
                <link>https://a.example/cdata</link>
                <description><![CDATA[The library supports <b>GGUF</b> inference &amp; fine-tuning.]]></description>
                <pubDate>Mon, 28 Sep 2026 10:00:00 GMT</pubDate>
            </item>
        </channel></rss>
        """
        let items = FeedParsing.parse(data: Data(xml.utf8), source: .openai)
        XCTAssertEqual(items.count, 1, "CDATA item must survive")
        XCTAssertEqual(items[0].title, "New open-source LLM toolkit")
        XCTAssertTrue(items[0].summary.contains("GGUF"), "CDATA description must be captured, got: \(items[0].summary)")
    }
}
