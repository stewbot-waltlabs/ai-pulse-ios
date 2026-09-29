# AI Pulse — native iOS client

Minimalistic, free aggregator for the latest AI news: provider blogs, Hacker
News, Reddit, and practitioner blogs. No sign-in, no accounts, no analytics, no
tracking. On-device classification ranks what's worth reading.

## Sources

15 feeds, all fetched client-side over HTTPS:

- Provider blogs: OpenAI, Anthropic, Google DeepMind, Google AI Blog, Meta AI,
  Mistral, xAI, Microsoft AI, NVIDIA, Hugging Face, Cohere
- Community: Hacker News (Algolia API), r/MachineLearning, r/LocalLLaMA,
  simonwillison.net

## The "jev" classifier

`AIPulseCore.JevClassifier` is a deterministic, typed-Swift classifier — not an
LLM call. It scores every story on:

- `relevance` (0…1) — AI-term matching with hard penalties for job ads, crypto
  spam, and paywall-only links
- `value` (0…1) — source authority, recency decay, engagement (HN points and
  comments), and new-software signals; gated by relevance
- `topics` — typed enum set (modelReleases, research, tooling, hardware,
  policy, benchmarks, opinion)

## Layout

| Target | Contents | Verified by |
| --- | --- | --- |
| `AIPulseCore` | Logic. No SwiftUI, no UIKit. Feeds, parsing, classifier, model, saved store. | `swift test`, CI |
| `AIPulseUI` | SwiftUI views: Pulse / Latest / Topics / Saved tabs, detail. | `swift test`, CI |
| `App/` | Thin `@main` entry point. | Xcode build |

## Build & test

Command line (no Xcode needed):

```
swift build && swift test
```

Full app (generated project is gitignored):

```
xcodegen generate
xcodebuild -project AIPulse.xcodeproj -scheme AIPulse \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
```

Or open `AIPulse.xcodeproj` in Xcode and press Cmd+R on a simulator — no
signing needed.
