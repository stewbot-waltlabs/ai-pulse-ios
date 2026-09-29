import Foundation
import Observation

/// Snapshot persisted to disk for offline display.
struct PulseSnapshot: Codable {
    var items: [ScoredItem]
    var savedAt: Date
}

/// Orchestrates fetching, classifying, deduping and ranking. UI-agnostic
/// (Foundation + Observation only - no SwiftUI/UIKit).
@Observable
@MainActor
public final class PulseModel {
    public private(set) var items: [ScoredItem] = []
    public private(set) var isStale = false
    public private(set) var isLoading = false
    public private(set) var lastError: String?

    /// Request-id guard: bump on every refresh; stale generations are dropped.
    private var generation = 0

    /// Snapshots older than this are flagged stale for the offline banner.
    static let staleThreshold: TimeInterval = 60 * 60

    private let fetcher: any FeedFetching
    private let classifier: JevClassifier
    private let cacheURL: URL?

    public init(fetcher: any FeedFetching, classifier: JevClassifier = JevClassifier(), cacheURL: URL? = nil) {
        self.fetcher = fetcher
        self.classifier = classifier
        self.cacheURL = cacheURL
    }

    // MARK: - Refresh

    public func refresh() async {
        generation += 1
        let myGeneration = generation
        isLoading = true
        lastError = nil

        var collected: [NewsItem] = []
        var errors: [String] = []

        await withTaskGroup(of: Result<[NewsItem], Error>.self) { group in
            for source in Source.allCases {
                group.addTask { [fetcher] in
                    do { return .success(try await fetcher.fetch(source)) }
                    catch { return .failure(error) }
                }
            }
            for await result in group {
                switch result {
                case .success(let items): collected.append(contentsOf: items)
                case .failure(let error): errors.append(String(describing: error))
                }
            }
        }

        // Request-id guard: a newer refresh superseded us.
        guard myGeneration == generation else { return }

        if collected.isEmpty, !errors.isEmpty {
            lastError = errors.first ?? "Network unavailable"
            isLoading = false
            if items.isEmpty, let cached = readSnapshot() {
                items = cached.items
            }
            // Whatever is on screen now came from an earlier fetch and the
            // network is down — that is exactly "stale".
            if !items.isEmpty { isStale = true }
            return
        }

        let now = Date.now
        let scored = classifyAndRank(collected, now: now)
        items = scored
        isStale = false
        isLoading = false
        writeSnapshot(PulseSnapshot(items: scored, savedAt: now))
    }

    /// Classify, dedupe (URL + normalized title), relevance-gate, sort by value.
    public func classifyAndRank(_ input: [NewsItem], now: Date = .now) -> [ScoredItem] {
        var seenURLs = Set<String>()
        var seenTitles = Set<String>()
        var out: [ScoredItem] = []
        // Deterministic dedupe: upstream fetch completion order is
        // nondeterministic (TaskGroup), so which of two same-title items
        // survives must not depend on arrival order.
        let input = input.sorted { $0.url.absoluteString < $1.url.absoluteString }
        for item in input {
            let key = item.url.absoluteString
            let titleKey = item.normalizedTitle
            // Title dedupe only for distinctive titles — short generic titles
            // ("Weekly discussion thread") from different orgs are distinct
            // stories and must not over-merge.
            let titleIsDedupeKey = item.titleIsDistinctiveForDedupe
            guard !seenURLs.contains(key),
                  !(titleIsDedupeKey && seenTitles.contains(titleKey)) else { continue }
            seenURLs.insert(key)
            if titleIsDedupeKey { seenTitles.insert(titleKey) }
            let score = classifier.classify(item, now: now)
            out.append(ScoredItem(item: item, score: score))
        }
        return out.sorted {
            if $0.score.value != $1.score.value { return $0.score.value > $1.score.value }
            return ($0.item.publishedAt ?? .distantPast) > ($1.item.publishedAt ?? .distantPast)
        }
    }

    // MARK: - Offline snapshot

    public func loadCachedIfAvailable() {
        guard items.isEmpty, let snapshot = readSnapshot() else { return }
        items = snapshot.items
        // Stale only when the snapshot is actually old — a fresh snapshot
        // (e.g. app relaunch right after a successful refresh) must not
        // show the offline banner.
        isStale = Date.now.timeIntervalSince(snapshot.savedAt) > Self.staleThreshold
    }

    private func readSnapshot() -> PulseSnapshot? {
        guard let cacheURL else { return nil }
        guard let data = try? Data(contentsOf: cacheURL) else { return nil }
        return try? JSONDecoder().decode(PulseSnapshot.self, from: data)
    }

    private func writeSnapshot(_ snapshot: PulseSnapshot) {
        guard let cacheURL else { return }
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        try? data.write(to: cacheURL, options: .atomic)
    }
}
