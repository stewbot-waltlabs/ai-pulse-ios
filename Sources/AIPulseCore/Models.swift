import Foundation

/// A single feed source. Typed, never stringly-typed.
public enum FeedKind: String, Codable, Sendable {
    case rss
    case atom
    case hnAlgolia
    case redditRSS
}

/// The catalog of sources AI Pulse pulls from.
public enum Source: String, CaseIterable, Codable, Sendable, Identifiable, Hashable {
    case openai
    case anthropic
    case googleDeepMind
    case googleAIBlog
    case metaAI
    case mistral
    case xai
    case microsoftAI
    case nvidia
    case huggingFace
    case cohere
    case hackerNews
    case redditMachineLearning
    case redditLocalLLaMA
    case simonwillison

    public var id: String { rawValue }

    /// Human-readable name shown in the UI.
    public var displayName: String {
        switch self {
        case .openai: "OpenAI"
        case .anthropic: "Anthropic"
        case .googleDeepMind: "Google DeepMind"
        case .googleAIBlog: "Google AI Blog"
        case .metaAI: "Meta AI"
        case .mistral: "Mistral"
        case .xai: "xAI"
        case .microsoftAI: "Microsoft AI"
        case .nvidia: "NVIDIA"
        case .huggingFace: "Hugging Face"
        case .cohere: "Cohere"
        case .hackerNews: "Hacker News"
        case .redditMachineLearning: "r/MachineLearning"
        case .redditLocalLLaMA: "r/LocalLLaMA"
        case .simonwillison: "simonwillison.net"
        }
    }

    public var kind: FeedKind {
        switch self {
        case .hackerNews: .hnAlgolia
        case .redditMachineLearning, .redditLocalLLaMA: .redditRSS
        default: .rss
        }
    }

    /// Authority weight used by the value score (0…1).
    public var authority: Double {
        switch self {
        case .openai, .anthropic, .googleDeepMind, .googleAIBlog, .metaAI,
             .mistral, .xai, .microsoftAI, .nvidia, .huggingFace, .cohere:
            0.95
        case .simonwillison: 0.9
        case .hackerNews: 0.75
        case .redditMachineLearning, .redditLocalLLaMA: 0.6
        }
    }

    /// The feed/endpoint URL for this source.
    /// All URLs verified live on 29 Sep 2026 (see Tests/AIPulseCoreTests/AccuracyTests.swift).
    public var url: URL {
        switch self {
        case .openai:
            URL(string: "https://openai.com/news/rss.xml")! // verified 200 text/xml
        case .anthropic:
            // DEGRADED: anthropic.com publishes no official RSS (all /rss paths 404).
            // Community mirror by the Alan Turing Institute, refreshed regularly
            // (latest item Jul 2026): https://github.com/alan-turing-institute/ai-rss-feeds
            URL(string: "https://raw.githubusercontent.com/alan-turing-institute/ai-rss-feeds/main/feeds/anthropic-news.xml")!
        case .googleDeepMind:
            URL(string: "https://deepmind.google/blog/rss.xml")! // verified 200 rss+xml
        case .googleAIBlog:
            URL(string: "https://blog.google/technology/ai/rss/")! // verified 200 xml
        case .metaAI:
            // ai.meta.com/blog/rss/ 404s; research.facebook.com/feed/ is Meta's
            // official research-blog RSS (verified 200 text/xml).
            URL(string: "https://research.facebook.com/feed/")!
        case .mistral:
            URL(string: "https://mistral.ai/rss.xml")! // verified 200 RSS 2.0 (news/rss.xml 404s)
        case .xai:
            // DEGRADED: x.ai publishes no official RSS (both /blog/rss.xml and
            // /news/rss.xml 404; site is JS-rendered). Alan Turing Institute
            // mirror (verified 200, latest item Jul 2026) used instead.
            URL(string: "https://raw.githubusercontent.com/alan-turing-institute/ai-rss-feeds/main/feeds/spacex-ai-news.xml")!
        case .microsoftAI:
            // blogs.microsoft.com/ai/feed/ is 410 Gone; the AI tag feed on the
            // official Microsoft blog is the live replacement (verified 200 RSS).
            URL(string: "https://blogs.microsoft.com/blog/tag/ai/feed/")!
        case .nvidia:
            URL(string: "https://blogs.nvidia.com/feed/")! // verified 200 rss+xml
        case .huggingFace:
            URL(string: "https://huggingface.co/blog/feed.xml")! // verified 200 rss+xml
        case .cohere:
            // DEGRADED: cohere.com serves HTML on every /rss path (no official
            // feed). Alan Turing Institute mirror (verified 200, fresh Jul 2026).
            URL(string: "https://raw.githubusercontent.com/alan-turing-institute/ai-rss-feeds/main/feeds/cohere-blog.xml")!
        case .hackerNews:
            // Algolia search-by-date for AI-related stories.
            URL(string: "https://hn.algolia.com/api/v1/search_by_date?query=%22AI%22%20OR%20%22LLM%22&tags=story&hitsPerPage=50")!
        case .redditMachineLearning:
            URL(string: "https://www.reddit.com/r/MachineLearning/new/.rss")!
        case .redditLocalLLaMA:
            URL(string: "https://www.reddit.com/r/LocalLLaMA/new/.rss")!
        case .simonwillison:
            URL(string: "https://simonwillison.net/atom/everything/")! // verified 200 xml
        }
    }
}

/// One news item, normalized across RSS / Atom / JSON sources.
/// Optional count fields are nil when unknown — never 0-as-fact.
public struct NewsItem: Identifiable, Hashable, Codable, Sendable {
    public var id: String
    public var title: String
    public var summary: String
    public var url: URL
    public var source: Source
    public var publishedAt: Date?
    public var engagement: Engagement?
    public var fetchedAt: Date

    public init(
        id: String = UUID().uuidString,
        title: String,
        summary: String = "",
        url: URL,
        source: Source,
        publishedAt: Date? = nil,
        engagement: Engagement? = nil,
        fetchedAt: Date = .now
    ) {
        self.id = id
        self.title = title
        self.summary = summary
        self.url = url
        self.source = source
        self.publishedAt = publishedAt
        self.engagement = engagement
        self.fetchedAt = fetchedAt
    }

    /// Point/comment counts; nil fields mean "unknown", not zero.
    public struct Engagement: Hashable, Codable, Sendable {
        public var points: Int?
        public var comments: Int?

        public init(points: Int? = nil, comments: Int? = nil) {
            self.points = points
            self.comments = comments
        }
    }
}

/// A classifier verdict for one item.
public struct ClassificationScore: Hashable, Codable, Sendable {
    public var relevance: Double
    public var value: Double
    public var topics: [Topic]

    public init(relevance: Double, value: Double, topics: [Topic]) {
        self.relevance = relevance
        self.value = value
        self.topics = topics
    }
}

/// Typed topic taxonomy — never stringly-typed.
public enum Topic: String, Codable, CaseIterable, Sendable, Hashable, Identifiable {
    case modelReleases
    case research
    case tooling
    case hardware
    case policy
    case benchmarks
    case opinion

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .modelReleases: "Model Releases"
        case .research: "Research"
        case .tooling: "Tooling"
        case .hardware: "Hardware"
        case .policy: "Policy"
        case .benchmarks: "Benchmarks"
        case .opinion: "Opinion"
        }
    }
}

/// An item paired with its classifier verdict.
public struct ScoredItem: Identifiable, Hashable, Codable, Sendable {
    public var item: NewsItem
    public var score: ClassificationScore

    public var id: String { item.id }

    public init(item: NewsItem, score: ClassificationScore) {
        self.item = item
        self.score = score
    }
}

extension NewsItem {
    /// Normalized title for dedupe (case/punctuation-insensitive).
    public var normalizedTitle: String {
        String(title.lowercased().map { $0.isLetter || $0.isNumber ? $0 : " " }
            .split(separator: " ").joined(separator: " "))
    }

    /// Titles at or above this token count are distinctive enough for
    /// title-based dedupe; shorter generic titles ("Weekly thread", "Update")
    /// would over-merge unrelated stories from different sources.
    static let dedupeMinimumTitleTokens = 4

    /// True when the title is long enough to be used as a dedupe key.
    public var titleIsDistinctiveForDedupe: Bool {
        normalizedTitle.split(separator: " ").count >= Self.dedupeMinimumTitleTokens
    }
}
