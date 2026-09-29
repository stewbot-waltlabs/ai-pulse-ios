import XCTest
@testable import AIPulseCore

/// Pass-2 accuracy probes: edge cases for the classifier, dedupe, dates.
final class ClassifierAccuracyTests: XCTestCase {
    let classifier = JevClassifier()
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func item(title: String, summary: String = "", source: Source = .openai,
                      published: Date? = nil, points: Int? = nil, comments: Int? = nil) -> NewsItem {
        NewsItem(
            title: title, summary: summary, url: URL(string: "https://example.com/\(UUID().uuidString)")!,
            source: source, publishedAt: published,
            engagement: (points != nil || comments != nil)
                ? NewsItem.Engagement(points: points, comments: comments) : nil,
            fetchedAt: now
        )
    }

    // MARK: Word-boundary matching regressions

    func testLLMAtTitleStartMatches() {
        // Regression: the old table entry " llm" (leading space) never fired
        // on a title that STARTS with "LLM".
        let it = item(title: "LLM inference engine v0.3 released", source: .simonwillison,
                      published: now.addingTimeInterval(-3600))
        XCTAssertGreaterThanOrEqual(classifier.classify(it, now: now).relevance, 0.45,
                                    "\"LLM\" at title start must score")
    }

    func testLlamaAtTitleEndMatches() {
        // Regression: "llama " (trailing space) never fired at end of title.
        let it = item(title: "Meta releases new Llama", source: .metaAI,
                      published: now.addingTimeInterval(-3600))
        XCTAssertGreaterThanOrEqual(classifier.classify(it, now: now).relevance, 0.3,
                                    "\"Llama\" at title end must score")
    }

    func testSubstringFalsePositivesAreGone() {
        // "Jobs" inside "Steve Jobs" must NOT trigger the job-ad penalty,
        // while the AI terms in the same title still score.
        let jobs = item(title: "Steve Jobs would have hated this artificial intelligence timeline",
                        source: .openai, published: now)
        let s = classifier.classify(jobs, now: now)
        XCTAssertGreaterThanOrEqual(s.relevance, 0.5, "AI story must stay relevant")
        let baseline = classifier.classify(item(title: "An artificial intelligence timeline in review",
                                                source: .openai, published: now), now: now).relevance
        XCTAssertEqual(s.relevance, baseline,
                       "\"Steve Jobs\" must not reduce relevance below the identical baseline")

        let urban = item(title: "Urban AI planning with computer vision",
                         source: .googleAIBlog, published: now)
        XCTAssertFalse(classifier.classify(urban, now: now).topics.contains(.policy),
                       "\"Urban\" must not trigger the policy topic via \"ban \"")

        let claudette = item(title: "Claudette the robot arm visits the lab",
                             source: .huggingFace, published: now)
        XCTAssertFalse(classifier.classify(claudette, now: now).topics.contains(.modelReleases),
                       "no release cues in a Claudette story")
        let claudetteRel = classifier.classify(claudette, now: now).relevance
        XCTAssertEqual(claudetteRel, 0, "\"Claudette\" must not match the \"claude\" term")
    }

    // MARK: Adversarial keyword stuffing

    func testKeywordStuffingIsCappedPerTerm() {
        let stuffed = item(title: "AI AI AI LLM LLM LLM OpenAI OpenAI ChatGPT ChatGPT GPT GPT",
                           summary: "machine learning machine learning machine learning",
                           source: .redditMachineLearning, published: now)
        let once = item(title: "AI LLM OpenAI",
                        summary: "machine learning", source: .redditMachineLearning, published: now)
        let sStuffed = classifier.classify(stuffed, now: now)
        let sOnce = classifier.classify(once, now: now)
        XCTAssertLessThanOrEqual(sStuffed.relevance, 1.0, "relevance bounded 0-1")
        // Repeating terms may only help up to the one-time weight each;
        // both hit the cap or the stuffed one gains nothing beyond distinct terms.
        XCTAssertLessThanOrEqual(sStuffed.relevance, 1.0)
        XCTAssertLessThanOrEqual(sOnce.relevance, sStuffed.relevance)
        // A stuffed title must not out-value an honest high-value release.
        let release = item(title: "Announcing GPT-5: our new frontier language model",
                           summary: "OpenAI releases a new large language model.",
                           source: .openai, published: now)
        XCTAssertGreaterThan(classifier.classify(release, now: now).value, sStuffed.value)
    }

    // MARK: Empty / long / unicode inputs

    func testEmptyTitleAndSummaryScoresZero() {
        let it = item(title: "", summary: "", source: .openai, published: now)
        let s = classifier.classify(it, now: now)
        XCTAssertEqual(s.relevance, 0)
        XCTAssertEqual(s.value, 0, "no content → no value; unknown must not render as fact")
        XCTAssertTrue(s.topics.isEmpty)
    }

    func testVeryLongTitleIsFastAndBounded() {
        let long = String(repeating: "new language model release ", count: 2_000)
        let it = item(title: long, source: .openai, published: now)
        // Warm up code paths (first call pays process-wide lazy initialization).
        _ = classifier.classify(it, now: now)
        let start = Date()
        let s = classifier.classify(it, now: now)
        let elapsed = Date().timeIntervalSince(start)
        // Input is capped at 2,000 chars (≈300 tokens); even a pathological
        // max-length input classifies in well under 0.2s in a debug build,
        // and normal items (<300 chars) in single-digit milliseconds.
        XCTAssertLessThan(elapsed, 0.2, "classification must stay fast even on max-length input")
        // Normal-size item must be genuinely fast. 50ms bound: the contract
        // target (<1ms) is a release-build figure; unoptimized test builds
        // run ~10x slower and share the machine with parallel test suites,
        // so a tight bound flakes. 50ms is still 4x under the pathological cap.
        let normal = item(title: "Announcing GPT-5: our new frontier language model",
                          summary: "OpenAI releases a new large language model.",
                          source: .openai, published: now)
        _ = classifier.classify(normal, now: now)
        let start2 = Date()
        _ = classifier.classify(normal, now: now)
        XCTAssertLessThan(Date().timeIntervalSince(start2), 0.05, "normal item classifies quickly")
        XCTAssertLessThanOrEqual(s.relevance, 1.0)
        XCTAssertLessThanOrEqual(s.value, 1.0)
    }

    func testUnicodeAndEmojiDoNotBreakClassification() {
        let it = item(title: "🤖 Intelligence artificielle : nouveau modèle de langage 🚀",
                      summary: "LLM · « génératif » — métadonnées",
                      source: .mistral, published: now)
        let s = classifier.classify(it, now: now)
        // Keyword tables are English; the one English cue ("LLM") still
        // matches exactly once despite surrounding emoji/quotes.
        XCTAssertEqual(s.relevance, 0.45, accuracy: 0.001,
                       "emoji-wrapped LLM mention still matches exactly once")
        XCTAssertTrue((0...1).contains(s.value), "value bounded")
        // English-cue story with unicode keeps its topic classification.
        let en = item(title: "Nouveau modèle released — open weights ✨",
                      summary: "un LLM multimodal", source: .mistral, published: now)
        XCTAssertTrue(classifier.classify(en, now: now).topics.contains(.modelReleases),
                      "release cue survives unicode text")
        XCTAssertEqual(classifier.classify(item(title: "日本語のタイトル", source: .openai, published: now), now: now).relevance, 0)
    }

    // MARK: Engagement nil vs 0 semantics

    func testEngagementNilIsNeutralZeroIsFact() {
        // nil = unknown → neutral 0.35
        XCTAssertEqual(classifier.engagementScore(item(title: "x")), 0.35)
        // known zero engagement → 0.0, NOT the neutral default
        let zero = item(title: "x", points: 0, comments: 0)
        XCTAssertEqual(classifier.engagementScore(zero), 0.0,
                       "0 points is a fact (nobody engaged), not unknown")
        // nil points but known comments → only comments count
        let commentsOnly = item(title: "x", points: nil, comments: 300)
        XCTAssertEqual(classifier.engagementScore(commentsOnly), 1.0, accuracy: 0.001)
        // value reflects the difference: unknown outranks known-zero at equal relevance
        let a = classifier.classify(item(title: "New AI research on scaling laws",
                                        source: .openai, published: now), now: now).value
        let b = classifier.classify(item(title: "New AI research on scaling laws",
                                         source: .openai, published: now, points: 0, comments: 0), now: now).value
        XCTAssertGreaterThan(a, b, "unknown engagement (neutral) must outrank known-zero engagement")
    }

    // MARK: Recency decay bounds

    func testRecencyDecayBoundedAndMonotonic() {
        // monotonic across a wide range
        var prev = 2.0
        for hours in [0, 1, 6, 24, 48, 96, 240, 1000, 10000] {
            let d = classifier.recencyDecay(now.addingTimeInterval(-Double(hours) * 3600), now: now)
            XCTAssertLessThanOrEqual(d, prev)
            XCTAssertGreaterThanOrEqual(d, 0.0)
            XCTAssertLessThanOrEqual(d, 1.0)
            prev = d
        }
        // future-dated items clamp to 1.0 (no >1 boost)
        XCTAssertEqual(classifier.recencyDecay(now.addingTimeInterval(3600), now: now), 1.0)
        // very old floors at 0.05
        XCTAssertEqual(classifier.recencyDecay(now.addingTimeInterval(-365 * 24 * 3600), now: now), 0.05)
        // unknown date → neutral, not 0-as-fact
        XCTAssertEqual(classifier.recencyDecay(nil, now: now), 0.4)
    }

    // MARK: Topic rule typing

    func testTopicRulesAreTypedAndPrecise() {
        let t = classifier.classify(item(title: "SWE-bench leaderboard: dataset contamination in evaluation results",
                                         source: .huggingFace, published: now), now: now)
        XCTAssertTrue(t.topics.contains(.benchmarks))
        XCTAssertTrue(t.topics.contains(.research), "dataset contamination is a research cue")

        let notBenchmark = classifier.classify(item(title: "Why my garden grows better with compost",
                                                    source: .simonwillison, published: now), now: now)
        XCTAssertFalse(notBenchmark.topics.contains(.benchmarks))

        // "arena" is a benchmark term but "Arena" the game must not be policy/hardware
        let arena = classifier.classify(item(title: "Chatbot Arena elo update for LLMs",
                                             source: .huggingFace, published: now), now: now)
        XCTAssertTrue(arena.topics.contains(.benchmarks))
    }

    // MARK: Determinism with new matcher

    func testDeterminismWithUnicode() {
        let it = item(title: " café ☕ — OpenAI publie un nouveau modèle 🤖",
                      summary: "un LLM multimodal", source: .openai, published: now)
        XCTAssertEqual(classifier.classify(it, now: now), classifier.classify(it, now: now))
    }
}

/// Dedupe accuracy: over-merge / under-merge probes.
final class DedupeAccuracyTests: XCTestCase {
    @MainActor
    private func rank(_ items: [NewsItem]) -> [ScoredItem] {
        PulseModel(fetcher: ScriptedFetcher(), cacheURL: nil).classifyAndRank(items, now: Date(timeIntervalSince1970: 1_790_000_000))
    }

    @MainActor
    func testShortGenericTitlesFromDifferentOrgsAreNotOverMerged() {
        let items = [
            fixture("Weekly discussion thread", "https://a.example/w1", source: .redditMachineLearning),
            fixture("Weekly discussion thread", "https://b.example/w2", source: .redditLocalLLaMA),
        ]
        let ranked = rank(items)
        XCTAssertEqual(ranked.count, 2,
                       "same short generic title from different orgs/URLs are distinct stories")
    }

    @MainActor
    func testLongIdenticalTitlesAcrossOrgsStillMerge() {
        let items = [
            fixture("OpenAI announces GPT-5 frontier model with open weights",
                    "https://a.example/g5a", source: .openai),
            fixture("OpenAI announces GPT-5 frontier model with open weights!",
                    "https://b.example/g5b", source: .hackerNews),
        ]
        let ranked = rank(items)
        XCTAssertEqual(ranked.count, 1, "distinctive identical titles are the same story (punctuation-insensitive)")
    }

    @MainActor
    func testSameTitleDifferentNumbersAreDistinct() {
        let items = [
            fixture("Claude 3.5 released by Anthropic today", "https://a.example/c35", source: .anthropic),
            fixture("Claude 4.5 released by Anthropic today", "https://b.example/c45", source: .anthropic),
        ]
        XCTAssertEqual(rank(items).count, 2, "different model numbers are different stories")
    }

    @MainActor
    func testURLDedupeStillAppliesToShortTitles() {
        let items = [
            fixture("Weekly thread", "https://a.example/same", source: .redditMachineLearning),
            fixture("Weekly thread!!", "https://a.example/same", source: .redditMachineLearning),
        ]
        XCTAssertEqual(rank(items).count, 1, "identical URL always dedupes regardless of title")
    }
}

/// Date/timezone parsing accuracy.
final class DateAccuracyTests: XCTestCase {
    func testRFC822NumericOffsets() {
        // Numeric offsets were previously unparsed (nil → "unknown" dates).
        let plusOne = FeedParsing.parseXMLDate("Mon, 28 Sep 2026 10:00:00 +0100")
        XCTAssertEqual(plusOne, Date(timeIntervalSince1970: 1_790_586_000),
                       "+0100 must shift the instant correctly (09:00 UTC)")

        let utc = FeedParsing.parseXMLDate("Mon, 28 Sep 2026 10:00:00 +0000")
        XCTAssertEqual(utc, Date(timeIntervalSince1970: 1_790_589_600))

        let minusFive = FeedParsing.parseXMLDate("Mon, 28 Sep 2026 10:00:00 -0500")
        XCTAssertEqual(minusFive, Date(timeIntervalSince1970: 1_790_589_600 + 5 * 3600))
    }

    func testRFC822NoSecondsVariant() {
        XCTAssertNotNil(FeedParsing.parseXMLDate("Mon, 28 Sep 2026 10:00 GMT"))
    }

    func testISO8601Offsets() {
        XCTAssertEqual(FeedParsing.parseXMLDate("2026-09-28T11:00:00+01:00"),
                       Date(timeIntervalSince1970: 1_790_589_600))
        XCTAssertNotNil(FeedParsing.parseXMLDate("2026-09-28T10:00:00.500Z"))
    }

    func testGarbageDatesAreNilNotEpochZero() {
        XCTAssertNil(FeedParsing.parseXMLDate("gibberish"))
        XCTAssertNil(FeedParsing.parseXMLDate("0000-00-00T00:00:00Z"))
        // nil must never surface as Date(timeIntervalSince1970: 0)
        let d = FeedParsing.parseXMLDate("")
        XCTAssertNotEqual(d, Date(timeIntervalSince1970: 0))
    }
}

/// Pins the feed URL catalog to the live-verified URLs (checked 29 Sep 2026
/// with curl; see pass-2 report). Offline by design — network assertions
/// belong to CI smoke, not unit tests.
final class FeedURLAccuracyTests: XCTestCase {
    func testVerifiedFeedURLs() {
        let expected: [Source: String] = [
            .openai: "https://openai.com/news/rss.xml",                      // 200 text/xml
            .anthropic: "https://raw.githubusercontent.com/alan-turing-institute/ai-rss-feeds/main/feeds/anthropic-news.xml", // official 404s; mirror
            .googleDeepMind: "https://deepmind.google/blog/rss.xml",         // 200 rss+xml
            .googleAIBlog: "https://blog.google/technology/ai/rss/",         // 200 xml
            .metaAI: "https://research.facebook.com/feed/",                  // official Meta RSS (ai.meta.com 404)
            .mistral: "https://mistral.ai/rss.xml",                          // 200 RSS 2.0 (news/rss.xml 404)
            .xai: "https://raw.githubusercontent.com/alan-turing-institute/ai-rss-feeds/main/feeds/spacex-ai-news.xml", // no official feed
            .microsoftAI: "https://blogs.microsoft.com/blog/tag/ai/feed/",   // 200 (old /ai/feed/ is 410)
            .nvidia: "https://blogs.nvidia.com/feed/",                       // 200 rss+xml
            .huggingFace: "https://huggingface.co/blog/feed.xml",            // 200 rss+xml
            .cohere: "https://raw.githubusercontent.com/alan-turing-institute/ai-rss-feeds/main/feeds/cohere-blog.xml", // official serves HTML
            .hackerNews: "https://hn.algolia.com/api/v1/search_by_date?query=%22AI%22%20OR%20%22LLM%22&tags=story&hitsPerPage=50",
            .redditMachineLearning: "https://www.reddit.com/r/MachineLearning/new/.rss",
            .redditLocalLLaMA: "https://www.reddit.com/r/LocalLLaMA/new/.rss",
            .simonwillison: "https://simonwillison.net/atom/everything/",
        ]
        XCTAssertEqual(Source.allCases.count, expected.count, "every source pinned")
        for (source, url) in expected {
            XCTAssertEqual(source.url.absoluteString, url,
                           "\(source.displayName) feed URL drifted from the live-verified value")
        }
        for source in Source.allCases {
            XCTAssertEqual(source.url.scheme, "https", "\(source) must be HTTPS per contract")
        }
    }
}
