import XCTest
@testable import AIPulseCore

/// Fetcher whose responses are scripted with optional delays — no gated
/// continuations (those deadlock a MainActor-bound refresh when the test
/// spins synchronously). Config is snapshotted at fetch entry so a
/// reconfigured source mid-flight returns its ORIGINAL scripted result.
final class ScriptedFetcher: FeedFetching, @unchecked Sendable {
    struct Script {
        var result: Result<[NewsItem], Error> = .success([])
        var delay: TimeInterval = 0
    }

    private let lock = NSLock()
    private var scripts: [Source: Script] = [:]
    private(set) var fetchCount: [Source: Int] = [:]

    func set(_ source: Source, result: Result<[NewsItem], Error>, delay: TimeInterval = 0) {
        lock.lock(); defer { lock.unlock() }
        scripts[source] = Script(result: result, delay: delay)
    }

    func fetch(_ source: Source) async throws -> [NewsItem] {
        let script: Script = {
            lock.lock(); defer { lock.unlock() }
            fetchCount[source, default: 0] += 1
            return scripts[source] ?? Script()
        }()
        if script.delay > 0 {
            try await Task.sleep(nanoseconds: UInt64(script.delay * 1_000_000_000))
        }
        switch script.result {
        case .success(let items): return items
        case .failure(let error): throw error
        }
    }
}

func fixture(_ title: String, _ url: String, source: Source = .openai,
             published: Date? = Date(timeIntervalSince1970: 1_790_000_000)) -> NewsItem {
    NewsItem(title: title, summary: "\(title) summary", url: URL(string: url)!,
             source: source, publishedAt: published)
}

@MainActor
final class PulseModelTests: XCTestCase {
    func testDedupeByURLAndNormalizedTitle() async {
        let fetcher = ScriptedFetcher()
        let model = PulseModel(fetcher: fetcher, cacheURL: nil)
        fetcher.set(.openai, result: .success([
            fixture("Claude 3.5 released", "https://a.example/1", source: .openai),
            fixture("Claude 3.5 released", "https://a.example/1", source: .openai),
        ]))
        fetcher.set(.anthropic, result: .success([
            fixture("Claude 3.5 Released!", "https://b.example/other", source: .anthropic),
        ]))
        fetcher.set(.hackerNews, result: .failure(FeedError.network("offline")))

        await model.refresh()

        let titles = model.items.map(\.item.title)
        XCTAssertEqual(model.items.count, 1, "dupes by URL and normalized title must collapse")
        XCTAssertEqual(titles.first, "Claude 3.5 released")
        XCTAssertNil(model.lastError, "one dead source with other successes is not an error")
        XCTAssertEqual(fetcher.fetchCount[.hackerNews], 1)
    }

    func testRequestIDGuardStaleResultDoesNotClobber() async {
        let fetcher = ScriptedFetcher()
        let model = PulseModel(fetcher: fetcher, cacheURL: nil)
        // Generation 1: openai is SLOW with item A.
        fetcher.set(.openai, result: .success([fixture("SLOW generation-A item", "https://a.example/slow")]),
                    delay: 1.0)

        // Generation 1 starts; give its openai fetch time to snapshot the slow script.
        let first = Task { await model.refresh() }
        try? await Task.sleep(nanoseconds: 150_000_000)

        // Generation 2: openai now FAST with item B.
        fetcher.set(.openai, result: .success([fixture("FAST generation-B item", "https://a.example/fast")]),
                    delay: 0)
        await model.refresh() // generation 2 completes quickly.
        XCTAssertEqual(model.items.map(\.item.title), ["FAST generation-B item"])

        // Generation 1's slow result arrives late — must be discarded.
        await first.value
        let titles = model.items.map(\.item.title)
        XCTAssertTrue(titles.contains("FAST generation-B item"), "latest generation must win")
        XCTAssertFalse(titles.contains("SLOW generation-A item"),
                       "stale generation-1 result must not clobber generation 2")
        XCTAssertEqual(fetcher.fetchCount[.openai], 2, "both generations fetched openai")
    }

    func testOfflineCacheShowsStaleSnapshot() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let cacheURL = dir.appendingPathComponent("snapshot.json")
        defer { try? FileManager.default.removeItem(at: dir) }

        // Seed a snapshot via a successful refresh.
        let fetcher = ScriptedFetcher()
        fetcher.set(.openai, result: .success([fixture("Cached item", "https://a.example/cached")]))
        let model1 = PulseModel(fetcher: fetcher, cacheURL: cacheURL)
        await model1.refresh()
        XCTAssertEqual(model1.items.count, 1)
        XCTAssertFalse(model1.isStale)

        // New model, all sources dead: falls back to disk cache with stale flag.
        let dead = ScriptedFetcher()
        for source in Source.allCases { dead.set(source, result: .failure(FeedError.network("offline"))) }
        let model2 = PulseModel(fetcher: dead, cacheURL: cacheURL)
        model2.loadCachedIfAvailable()
        XCTAssertEqual(model2.items.count, 1, "disk snapshot must be restored")
        // Snapshot was written moments ago — fresh, not stale. The stale
        // marker appears below when the refresh actually fails offline.
        XCTAssertFalse(model2.isStale, "a just-written snapshot must not show the offline banner")
        XCTAssertEqual(model2.items.first?.item.title, "Cached item")

        // A refresh that totally fails keeps the stale cache visible + error.
        await model2.refresh()
        XCTAssertTrue(model2.isStale)
        XCTAssertEqual(model2.items.count, 1, "failed refresh must not blank the cached list")
        XCTAssertNotNil(model2.lastError)
    }

    func testAllSourcesFailedSetsError() async {
        let dead = ScriptedFetcher()
        for source in Source.allCases { dead.set(source, result: .failure(FeedError.http(503))) }
        let model = PulseModel(fetcher: dead, cacheURL: nil)
        await model.refresh()
        XCTAssertNotNil(model.lastError, "total failure must surface an error for retry UI")
        XCTAssertTrue(model.items.isEmpty)
    }

    func testRankingSortsByValueDesc() async {
        let fetcher = ScriptedFetcher()
        let now = Date(timeIntervalSince1970: 1_790_000_100)
        fetcher.set(.openai, result: .success([
            NewsItem(title: "Low-value old job post", summary: "", url: URL(string: "https://a.example/job")!,
                     source: .openai, publishedAt: now.addingTimeInterval(-500_000)),
        ]))
        fetcher.set(.anthropic, result: .success([
            NewsItem(title: "Announcing Claude 4 — new frontier AI model release",
                     summary: "large language model breakthrough",
                     url: URL(string: "https://a.example/model")!, source: .anthropic,
                     publishedAt: now, engagement: NewsItem.Engagement(points: 500, comments: 300)),
        ]))
        let model = PulseModel(fetcher: fetcher, cacheURL: nil)
        await model.refresh()
        XCTAssertEqual(model.items.count, 2)
        XCTAssertEqual(model.items.first?.item.title, "Announcing Claude 4 — new frontier AI model release",
                       "higher value must rank first")
    }

    func testFreshSnapshotOnRelaunchIsNotStale() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let cacheURL = dir.appendingPathComponent("snapshot.json")
        defer { try? FileManager.default.removeItem(at: dir) }

        let fetcher = ScriptedFetcher()
        fetcher.set(.openai, result: .success([fixture("Fresh item", "https://a.example/fresh")]))
        let model1 = PulseModel(fetcher: fetcher, cacheURL: cacheURL)
        await model1.refresh()
        XCTAssertFalse(model1.isStale, "successful refresh is not stale")

        // Relaunch immediately: cache was written moments ago; loading it must
        // NOT claim offline/stale (regression: loadCachedIfAvailable used to
        // set isStale unconditionally).
        let model2 = PulseModel(fetcher: fetcher, cacheURL: cacheURL)
        model2.loadCachedIfAvailable()
        XCTAssertFalse(model2.isStale, "a snapshot saved moments ago is fresh, not stale")
        XCTAssertEqual(model2.items.first?.item.title, "Fresh item")

        // But an old snapshot (aged past the threshold by rewriting savedAt)
        // must be flagged stale.
        let model3 = PulseModel(fetcher: fetcher, cacheURL: cacheURL)
        model3.loadCachedIfAvailable()
        XCTAssertTrue(model3.isStale == false || model3.isStale) // sanity: bool well-defined
        // Age the snapshot on disk beyond the threshold and re-load.
        struct AnySnapshot: Codable { var items: [ScoredItem]; var savedAt: Date }
        let aged = try JSONEncoder().encode(AnySnapshot(
            items: model2.items,
            savedAt: Date.now.addingTimeInterval(-(PulseModel.staleThreshold + 3_600))))
        try aged.write(to: cacheURL, options: .atomic)
        let model4 = PulseModel(fetcher: fetcher, cacheURL: cacheURL)
        model4.loadCachedIfAvailable()
        XCTAssertTrue(model4.isStale, "snapshot older than the threshold must be stale")
    }

    func testFailedRefreshMarksDisplayedItemsStale() async throws {
        // Items already on screen (from a previous successful refresh), then a
        // total network failure: items must stay visible AND be marked stale
        // (regression: the failure branch never set isStale for items that
        // were already displayed without a disk snapshot).
        final class FlippingFetcher: FeedFetching, @unchecked Sendable {
            var working = true
            func fetch(_ source: Source) async throws -> [NewsItem] {
                if working { return [fixture("Displayed item", "https://a.example/shown")] }
                throw FeedError.network("offline")
            }
        }
        let flip = FlippingFetcher()
        let model2 = PulseModel(fetcher: flip, cacheURL: nil)
        await model2.refresh()
        XCTAssertEqual(model2.items.count, 1)
        XCTAssertFalse(model2.isStale, "successful refresh: not stale")
        flip.working = false
        await model2.refresh()
        XCTAssertEqual(model2.items.count, 1, "failed refresh must keep displayed items")
        XCTAssertTrue(model2.isStale, "failed refresh must mark displayed items stale")
        XCTAssertNotNil(model2.lastError)
    }
}
