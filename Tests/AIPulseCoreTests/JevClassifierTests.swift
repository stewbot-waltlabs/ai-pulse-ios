import XCTest
@testable import AIPulseCore

final class JevClassifierTests: XCTestCase {
    let classifier = JevClassifier()
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func item(title: String, summary: String = "", source: Source = .openai,
                      published: Date? = nil, points: Int? = nil, comments: Int? = nil) -> NewsItem {
        NewsItem(
            title: title, summary: summary, url: URL(string: "https://example.com/x")!,
            source: source, publishedAt: published,
            engagement: (points != nil || comments != nil)
                ? NewsItem.Engagement(points: points, comments: comments) : nil,
            fetchedAt: now
        )
    }

    func testHighValueModelRelease() {
        let it = item(title: "Announcing GPT-5: our new frontier language model",
                      summary: "OpenAI releases a new large language model with improved reasoning.",
                      source: .openai, published: now.addingTimeInterval(-3600))
        let s = classifier.classify(it, now: now)
        XCTAssertGreaterThanOrEqual(s.relevance, 0.8, "model release should be highly relevant")
        XCTAssertGreaterThan(s.value, 0.6, "fresh model release from OpenAI should be high value")
        XCTAssertTrue(s.topics.contains(.modelReleases))
    }

    func testJobAdIsLow() {
        let it = item(title: "We're hiring: senior engineering role on our ML team",
                      summary: "Join our team. Apply now. Salary competitive.", source: .metaAI,
                      published: now.addingTimeInterval(-600))
        let s = classifier.classify(it, now: now)
        XCTAssertLessThan(s.relevance, 0.3, "job ads must be strongly penalized")
        XCTAssertLessThan(s.value, 0.4)
    }

    func testCryptoSpamIsLow() {
        let it = item(title: "Crypto bitcoin NFT web3 airdrop — get rich with AI trading signals",
                      summary: "blockchain defi token sale", source: .redditLocalLLaMA,
                      published: now)
        let s = classifier.classify(it, now: now)
        XCTAssertEqual(s.relevance, 0, "crypto spam must be zeroed out")
        XCTAssertLessThan(s.value, 0.15)
    }

    func testNewOSSToolHighValueAndToolingTopic() {
        let it = item(title: "I open-sourced a new local LLM inference toolkit on GitHub",
                      summary: "The library supports GGUF quantized models, fine-tuning and vLLM-style serving.",
                      source: .simonwillison, published: now.addingTimeInterval(-7200))
        let s = classifier.classify(it, now: now)
        XCTAssertTrue(s.topics.contains(.tooling), "OSS release should classify as tooling")
        XCTAssertGreaterThan(s.value, 0.5, "new software should score well")
    }

    func testDeterminism() {
        let it = item(title: "New benchmark results for Claude on SWE-bench",
                      summary: "evaluation of the language model on coding tasks", source: .anthropic,
                      published: now.addingTimeInterval(-1000), points: 420, comments: 88)
        let a = classifier.classify(it, now: now)
        let b = classifier.classify(it, now: now)
        XCTAssertEqual(a, b, "same input must yield identical output")
    }

    func testRecencyDecayMonotonic() {
        let offsets: [TimeInterval] = [0, 3600, 86_400, 172_800, 604_800]
        var previous = 2.0
        for offset in offsets {
            let d = classifier.recencyDecay(now.addingTimeInterval(-offset), now: now)
            XCTAssertLessThanOrEqual(d, previous, "decay must be monotonically non-increasing")
            previous = d
        }
        XCTAssertGreaterThan(classifier.recencyDecay(now, now: now), 0.99)
        XCTAssertNotNil(classifier.recencyDecay(nil, now: now), "unknown date is neutral, not nil")
    }

    func testEngagementNormalization() {
        XCTAssertEqual(classifier.engagementScore(item(title: "x", points: nil, comments: nil)), 0.35,
                       "unknown engagement is neutral")
        let high = classifier.engagementScore(item(title: "x", points: 500, comments: 300))
        XCTAssertEqual(high, 1.0, accuracy: 0.001, "500pts/300comments saturates")
        let low = classifier.engagementScore(item(title: "x", points: 25, comments: 9))
        XCTAssertLessThan(low, 0.3)
        let mid = classifier.engagementScore(item(title: "x", points: 100, comments: 100))
        XCTAssertGreaterThan(mid, low)
    }

    func testRelevanceGateSuppressesValue() {
        let relevant = item(title: "DeepMind publishes new AI research on scaling laws",
                            source: .googleDeepMind, published: now)
        let irrelevant = item(title: "Quarterly earnings call transcript", source: .nvidia, published: now)
        let r = classifier.classify(relevant, now: now)
        let i = classifier.classify(irrelevant, now: now)
        XCTAssertGreaterThan(r.value, i.value, "relevant items outrank irrelevant even at same authority/recency")
    }

    func testTopicsTypedRules() {
        let hardware = item(title: "NVIDIA announces new Blackwell GPU chip for AI datacenters",
                            source: .nvidia, published: now)
        XCTAssertTrue(classifier.classify(hardware, now: now).topics.contains(.hardware))
        let policy = item(title: "EU AI Act: new regulation and licensing policy for AI",
                          source: .microsoftAI, published: now)
        XCTAssertTrue(classifier.classify(policy, now: now).topics.contains(.policy))
        let research = item(title: "New paper on arXiv: we propose a method for ablation studies",
                            source: .huggingFace, published: now)
        XCTAssertTrue(classifier.classify(research, now: now).topics.contains(.research))
    }
}
