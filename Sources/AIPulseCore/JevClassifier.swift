import Foundation

/// The "jev" typesafe classifier: deterministic, on-device, keyword-table
/// driven. No LLM, no regex backtracking — plain `contains` over typed rules.
public struct JevClassifier: Sendable {
    public init() {}

    // MARK: - Typed keyword tables (static data)

    /// Strong AI signal phrases. Matched case-insensitively via contains.
    static let coreTerms: [(phrase: String, weight: Double)] = [
        ("artificial intelligence", 0.5),
        ("machine learning", 0.4),
        ("llm", 0.45), ("large language model", 0.5), ("language model", 0.35),
        ("neural network", 0.3), ("deep learning", 0.3),
        ("generative ai", 0.5), ("foundation model", 0.45),
        ("reinforcement learning", 0.3), ("computer vision", 0.25),
        ("transformer", 0.3), ("diffusion model", 0.3), ("multimodal", 0.3),
        ("openai", 0.35), ("gpt-", 0.4), ("chatgpt", 0.35),
        ("anthropic", 0.35), ("claude", 0.3),
        ("gemini", 0.3), ("deepmind", 0.3),
        ("llama", 0.3), ("mistral", 0.25), ("grok", 0.2),
        ("ai model", 0.4), ("ai research", 0.4), ("ai system", 0.3),
    ]

    /// Model-release signal. Word-boundary matched; stems listed in
    /// `stemPrefixes` ("announc" → "announces/announced") keep their reach.
    static let releaseTerms: [String] = [
        "announc", "introduc", "releas", "launch", "unveil", "ships", "shipping",
        "now available", "open weights", "open source", "open-source", "checkpoint",
        "new model", "state-of-the-art", "frontier",
    ]

    /// New useful software signal.
    static let softwareTerms: [String] = [
        "github", "open source", "open-source", "oss", "release", "v1.", "v2.",
        "toolkit", "sdk", "library", "framework", "cli", "benchmark", "inference",
        "fine-tune", "fine-tuned", "fine-tuning", "finetun", "quantiz", "gguf", "onnx", "vllm",
        "open weights", "developer tool", "mlops", "run locally", "self-host",
    ]

    /// Hardware signal.
    static let hardwareTerms: [String] = [
        "gpu", "tpu", "npu", "chip", "accelerator", "silicon", "cuda", "datacenter",
        "data center", "h100", "h200", "b200", "blackwell", "grace", "tpu v",
        "inference hardware", "nvidia",
    ]

    /// Policy / regulation signal.
    static let policyTerms: [String] = [
        "regulat", "legislation", "policy", "law", "laws", "bans", "banned", "banning",
        "govern", "eu ai act", "copyright", "lawsuit", "safety institute", "executive order",
        "licens", "compliance", "antitrust",
    ]

    /// Benchmarks signal.
    static let benchmarkTerms: [String] = [
        "benchmark", "mmlu", "gsm8k", "humaneval", "swe-bench", "arena", "elo",
        "leaderboard", "eval", "evaluation result", "contamination",
    ]

    /// Research signal.
    static let researchTerms: [String] = [
        "paper", "arxiv", "we propose", "we show", "study ", "research",
        "ablation", "dataset", "method", "scaling law",
    ]

    /// Opinion signal.
    static let opinionTerms: [String] = [
        "why ", "thoughts on", "opinion", "my take", "hot take", "essay",
        "reflection", "in defense of", "against ",
    ]

    /// Hard penalties: strongly down-rank these categories. Word-boundary
    /// matched, so "Jobs" in "Steve Jobs" never fires (bare "job"/"jobs" are
    /// deliberately excluded — real job ads still hit via the phrases below).
    static let jobAdTerms: [String] = [
        "we're hiring", "we are hiring", "hiring", "careers", "apply now",
        "join our team", "open position", "open positions", "job opening", "job openings",
        "senior role", "engineering role", "salary", "resume", "vacanc", "recruit",
    ]

    static let cryptoSpamTerms: [String] = [
        "crypto", "bitcoin", "nft", "nfts", "web3", "token sale", "airdrop",
        "blockchain", "decentralized finance", "get rich", "to the moon",
    ]

    static let paywallTerms: [String] = [
        "subscribe to read", "paywall", "subscribers only", "sign up to continue",
    ]

    // MARK: - Matching helpers

    /// Lowercased text reduced to word tokens. Non-alphanumerics become
    /// separators, so "GPT-5" → ["gpt","5"] and "we're" → ["we","re"].
    static func tokenized(_ text: String) -> [String] {
        text.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init)
    }

    /// Words allowed to match as STEM PREFIXES ("releas" → "releases").
    /// Everything else matches whole tokens only, so "claude" can never
    /// prefix-match "claudette" and "arena" never matches "arenas"... unless
    /// listed here. Keep this list short and deliberate.
    static let stemPrefixes: Set<String> = [
        "announc", "introduc", "releas", "launch", "unveil", "ship",
        "finetun", "quantiz", "transformer", "accelerator", "chip",
        "regulat", "govern", "licens", "benchmark", "eval", "method",
        "vacanc", "recruit", "model",
    ]

    /// Penalty hit count using stem-aware token matching.
    private static func penaltyHits(_ terms: [String], ngrams: MatchIndex) -> Int {
        terms.filter { ngrams.contains(term: $0, stemPrefixes: stemPrefixes) }.count
    }

    /// Precomputed match index for one document. `exactGrams` holds every
    /// n-gram (spans 1…4) of full tokens; `stemGrams` holds the same n-grams
    /// with the final token replaced by any stem prefix it extends ("models"
    /// contributes "model"). Term lookups are O(1) set hits and stem
    /// semantics apply ONLY to words in `stemPrefixes` — "claude" can never
    /// match "claudette".
    struct MatchIndex {
        private var exactGrams: Set<String> = []
        private var stemGrams: Set<String> = []

        init(tokens: [String], stemPrefixes: Set<String>) {
            guard !tokens.isEmpty else { return }
            let maxSpan = 4
            let prefixList = stemPrefixes.sorted()
            for span in 1...min(maxSpan, tokens.count) {
                for start in 0...tokens.count - span {
                    let head = tokens[start..<start + span - 1].map { String($0) }
                    let last = tokens[start + span - 1]
                    let headKey = head.joined(separator: " ")
                    let exact = headKey.isEmpty ? last : headKey + " " + last
                    exactGrams.insert(exact)
                    for stem in prefixList where last.hasPrefix(stem) {
                        let stemKey = headKey.isEmpty ? stem : headKey + " " + stem
                        stemGrams.insert(stemKey)
                    }
                }
            }
        }

        /// Does `term` (raw table entry, any case/hyphenation) match?
        func contains(term: String, stemPrefixes: Set<String>) -> Bool {
            let words = term.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init)
            guard !words.isEmpty else { return false }
            let key = words.joined(separator: " ")
            if exactGrams.contains(key) { return true }
            guard stemPrefixes.contains(words[words.count - 1]) else { return false }
            return stemGrams.contains(key)
        }
    }

    /// Back-compatible linear matcher (used by isSoftware and tests).
    static func containsTerm(_ term: String, tokens: [String], tokenSet: Set<String>? = nil) -> Bool {
        let words = tokenized(term)
        guard !words.isEmpty, tokens.count >= words.count else { return false }
        if words.count == 1 {
            let word = words[0]
            if Self.stemPrefixes.contains(word) {
                return tokens.contains { $0 == word || $0.hasPrefix(word) }
            }
            return (tokenSet ?? Set(tokens)).contains(word)
        }
        let span = words.count
        for start in 0...tokens.count - span {
            var ok = true
            for (offset, word) in words.enumerated() {
                let tok = tokens[start + offset]
                let lastMatches = tok == word
                    || (offset == span - 1 && Self.stemPrefixes.contains(word) && tok.hasPrefix(word))
                if !lastMatches { ok = false; break }
            }
            if ok { return true }
        }
        return false
    }

    // MARK: - API

    public func classify(_ item: NewsItem, now: Date = .now) -> ClassificationScore {
        // Bound pathological input: only the first N characters of title +
        // summary are classified (titles are <300 chars in practice; feeds
        // occasionally ship enormous auto-generated summaries that would make
        // the token scan needlessly slow). Content past the cap is ignored.
        let raw = String((item.title + " \n " + item.summary).prefix(2_000))
        let tokens = Self.tokenized(raw)
        let index = MatchIndex(tokens: tokens, stemPrefixes: Self.stemPrefixes)
        var topics: Set<Topic> = []

        // Relevance: core-term accumulation, capped, minus penalties.
        // Stuffing the same keyword N times cannot exceed the per-term weight
        // (each term counts at most once). Token matching means "llm" fires on
        // "LLM inference" (title-leading) and "gpt-" on "GPT-5", while "claude"
        // no longer matches "claudette".
        var relevance = 0.0
        for term in Self.coreTerms where index.contains(term: term.phrase, stemPrefixes: Self.stemPrefixes) {
            relevance += term.weight
        }
        relevance = min(relevance, 1.0)

        let jobHits = Self.penaltyHits(Self.jobAdTerms, ngrams: index)
        let cryptoHits = Self.penaltyHits(Self.cryptoSpamTerms, ngrams: index)
        let paywallHits = Self.penaltyHits(Self.paywallTerms, ngrams: index)
        relevance -= Double(jobHits) * 0.35
        relevance -= Double(cryptoHits) * 0.8
        relevance -= Double(paywallHits) * 0.3
        relevance = max(0, min(relevance, 1.0))

        // Topics — token-aware matching (no substring false positives).
        if Self.releaseTerms.contains(where: { index.contains(term: $0, stemPrefixes: Self.stemPrefixes) }) { topics.insert(.modelReleases) }
        if Self.softwareTerms.contains(where: { index.contains(term: $0, stemPrefixes: Self.stemPrefixes) }) { topics.insert(.tooling) }
        if Self.hardwareTerms.contains(where: { index.contains(term: $0, stemPrefixes: Self.stemPrefixes) }) { topics.insert(.hardware) }
        if Self.policyTerms.contains(where: { index.contains(term: $0, stemPrefixes: Self.stemPrefixes) }) { topics.insert(.policy) }
        if Self.benchmarkTerms.contains(where: { index.contains(term: $0, stemPrefixes: Self.stemPrefixes) }) { topics.insert(.benchmarks) }
        if Self.researchTerms.contains(where: { index.contains(term: $0, stemPrefixes: Self.stemPrefixes) }) { topics.insert(.research) }
        if Self.opinionTerms.contains(where: { index.contains(term: $0, stemPrefixes: Self.stemPrefixes) }) { topics.insert(.opinion) }

        // Value: authority, recency, engagement, new-software.
        var value = item.source.authority * 0.4
        value += recencyDecay(item.publishedAt, now: now) * 0.3
        value += engagementScore(item) * 0.2
        if isSoftware(item) { value += 0.15 }
        // Gate by relevance: irrelevant items cannot be high-value.
        // Hard floor at zero relevance (spam must not ride authority/recency).
        value *= relevance < 0.05 ? 0 : (0.3 + 0.7 * relevance)
        value = max(0, min(value, 1.0))

        return ClassificationScore(relevance: relevance, value: value, topics: topics.sorted { $0.rawValue < $1.rawValue })
    }

    /// Exponential decay: 1.0 at publish time, ~0.05 after 7 days, flat 0.05
    /// for older. Unknown date contributes a neutral 0.4 — NOT 0-as-fact.
    public func recencyDecay(_ date: Date?, now: Date = .now) -> Double {
        guard let date else { return 0.4 }
        let age = now.timeIntervalSince(date)
        if age <= 0 { return 1.0 }
        let halfLife: TimeInterval = 60 * 60 * 24 * 1.5 // ~1.5-day half-life.
        let decay = pow(0.5, age / halfLife)
        return max(decay, 0.05)
    }

    /// Engagement normalized against a HN-points scale; nil stays nil→neutral.
    public func engagementScore(_ item: NewsItem) -> Double {
        guard let engagement = item.engagement,
              engagement.points != nil || engagement.comments != nil else { return 0.35 } // unknown → neutral
        var parts: [Double] = []
        if let points = engagement.points {
            // 500+ points saturates; sqrt curve favors small deltas.
            parts.append(min(sqrt(Double(max(points, 0))) / sqrt(500), 1.0))
        }
        if let comments = engagement.comments {
            parts.append(min(sqrt(Double(max(comments, 0))) / sqrt(300), 1.0))
        }
        guard !parts.isEmpty else { return 0.35 }
        return parts.reduce(0, +) / Double(parts.count)
    }

    public func isSoftware(_ item: NewsItem) -> Bool {
        // Same 2,000-char cap as classify() — the linear fallback scan is
        // O(terms × tokens) and pathological summaries would dominate.
        let raw = String((item.title + " \n " + item.summary).prefix(2_000))
        let tokens = Self.tokenized(raw)
        let index = MatchIndex(tokens: tokens, stemPrefixes: Self.stemPrefixes)
        return Self.softwareTerms.contains { index.contains(term: $0, stemPrefixes: Self.stemPrefixes) }
    }
}