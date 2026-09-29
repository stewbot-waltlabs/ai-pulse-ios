# AI Pulse — Web Product Contract

There is **no existing web product** — AI Pulse is a greenfield native app. This contract
replaces the usual web-repo inventory with the product definition agreed with Stewart
(29 Sep 2026) and the architectural rules inherited from the Cloud Companion iOS template
(`templates/cloud-companion-ios` → `carbon-ios`).

## Product

- **Name:** AI Pulse
- **Bundle ID:** `com.waltlabs.aipulse` (prefix `com.waltlabs`)
- **Price:** Free. **No sign-in, no accounts, no analytics, no tracking.** Privacy manifest
  must declare network access only.
- **Purpose:** Minimalistic aggregator that pulls the latest news about AI from provider
  blogs and social/web sources, surfaces high-value topics and new useful software.

## Sources (RSS/Atom/JSON, fetched client-side)

Provider blogs: OpenAI, Anthropic, Google (DeepMind + Google AI blog), Meta AI,
Mistral, xAI, Microsoft (AI blog), NVIDIA blog, Hugging Face, Cohere.
Community/social: Hacker News (Algolia API `https://hn.algolia.com/api/v1/search_by_date?query=...&tags=story`),
r/MachineLearning + r/LocalLLaMA RSS (`https://www.reddit.com/r/<sub>/new/.rss`),
simonwillison.net RSS. All feeds over HTTPS.

## Classifier ("jev" typesafe classifier)

Deterministic, **on-device, typed Swift** scoring — NOT an LLM call, no API key shipped.
`AIPulseCore.JevClassifier` scores every `NewsItem`:

- `relevance: Double` (0…1) — keyword/phrase weighting for AI-provider terms, model
  releases, research themes; strongly penalizes job ads, crypto spam, paywall-only.
- `value: Double` (0…1) — weights: source authority, recency decay, engagement signals
  (HN points/comments where available), is-new-software signal (release/GitHub/open-source cues).
- `topics: [Topic]` — typed enum set (modelReleases, research, tooling, hardware,
  policy, benchmarks, opinion) via typed rules, never stringly-typed.
- Output is a `typed ClassificationScore` struct; fully unit-testable, fast (<ms per item).

## Screens (SwiftUI)

1. **Pulse (For You)** — items ranked by `value` (relevance gate first). Pull-to-refresh,
   relative timestamps, source badge, topic chips. Offline: show cached with stale marker.
2. **Latest** — chronological feed from all sources, filter by source/topic.
3. **Topics** — grouped by topic, trending = topic frequency growth in window.
4. **Saved** — local SwiftData persistence, swipe to remove, no account.
5. **Detail** — in-app summary; "Read" opens `SFSafariViewController`/`openURL`.

## Non-negotiable behaviors (from template lessons)

- Missing values render as unavailable — never 0 or empty-as-fact.
- Every async screen model uses a request-id guard so stale fetches can't render.
- Network failures show retry, not silent blank.
- No 401-expiry logic (no auth exists).
- Persistence is local only (SwiftData); no remote sync.

## Verification

`swift build && swift test` (Core+UI, no Xcode), then `xcodegen generate` +
`xcodebuild … -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test` when needed.
CI: `.github/workflows/ci.yml` (adapted from template).
