import XCTest
import Foundation
@testable import AIPulseCore

final class FeedFetchingTests: XCTestCase {
    struct StaticFeedFetcher: FeedFetching {
        var result: Result<[NewsItem], Error>
        func fetch(_ source: Source) async throws -> [NewsItem] {
            switch result {
            case .success(let items): return items
            case .failure(let error): throw error
            }
        }
    }

    func testFeedErrorEquality() {
        XCTAssertEqual(FeedError.http(503), FeedError.http(503))
        XCTAssertNotEqual(FeedError.http(503), FeedError.network("x"))
    }

    func testSourceCatalogIntegrity() {
        XCTAssertEqual(Source.allCases.count, 15, "contract source list must be complete")
        for source in Source.allCases {
            XCTAssertTrue(source.url.scheme == "https", "\(source) must use HTTPS")
            XCTAssertGreaterThan(source.authority, 0)
            XCTAssertFalse(source.displayName.isEmpty)
        }
        XCTAssertTrue(Source.allCases.contains(.hackerNews))
        XCTAssertEqual(Source.hackerNews.kind, .hnAlgolia)
        XCTAssertEqual(Source.redditLocalLLaMA.kind, .redditRSS)
    }

    func testNewsItemNormalizedTitle() {
        let a = fixture("Hello,  World! (v2)", "https://a.example/n1")
        let b = fixture("hello world v2", "https://a.example/n2")
        XCTAssertEqual(a.normalizedTitle, b.normalizedTitle)
    }
}
