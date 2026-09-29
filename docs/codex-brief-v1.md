# CODEx TASK: Build AI Pulse v1 (full rebrand + implementation)

You are working in `/Users/stewartsmith/ios-agent-workspace/apps/ai-pulse-ios` — a fresh copy
of the Cloud Companion iOS template (`carbon-ios` structure). Rebrand it to **AI Pulse** and
implement the product. Read `docs/web-product-contract.md` first — it is the product spec.

## Step 1 — Structural rebrand (delete template product code)

The template is a FinOps client for a cloud portal. AI Pulse needs NONE of that product code.
Delete `Sources/CloudCompanionCore` product files (APIClient, AlertRules, Assistant*, Auth/,
Customer*, GCP*, Roles, SessionExpiry, Support*, Trend*, AlertConfigForm, DocsNavigation,
NavigationMenu, etc.) and `Sources/CloudCompanionUI` screens. KEEP the architectural shape:

- SwiftPM package with `AIPulseCore` (logic, imports neither SwiftUI nor UIKit) and
  `AIPulseUI` (SwiftUI views) targets; thin `App/` entry point; `UITests/`.
- `project.yml` (XcodeGen): name `AIPulse`, bundleIdPrefix `com.waltlabs`, deploymentTarget iOS 17.
- Rename everywhere: CloudCompanion* → AIPulse*, Cloud Companion → AI Pulse, io.waltcompanion →
  com.waltlabs, waltcompanion → waltlabs. App entry file `AIPulseApp.swift`.
- Keep/ adapt `.github/workflows/ci.yml`, `.gitleaks.toml`, `.gitignore`, `Configs/` examples
  (Signing.xcconfig can stay gitignored-ish empty; no signing values — do NOT invent any).
- Update `README.md` for AI Pulse (free app, no sign-in, sources, classifier).
- Delete `Scripts/deploy-to-phone.sh`, `Scripts/release-testflight.sh` (signing-dependent).
- After rebrand: `grep -ri "cloudcompanion\|waltcompanion\|cloud companion\|carbon" .`
  must return nothing (except docs/web-product-contract.md template-history mentions).

## Step 2 — Core (`Sources/AIPulseCore`)

1. `NewsItem`: `id, title, summary, url, source (Source), publishedAt, engagement?
   (points/comments), fetchedAt`. All optional financial/count fields are `nil`-able —
   NEVER default to 0 where "unknown" is meant.
2. `Source`: typed enum with display name + feed kind (rss | hnAlgolia | redditRSS) and URL.
3. `Feeds.swift`: the source list per contract (OpenAI, Anthropic, Google DeepMind,
   Google AI blog, Meta AI, Mistral, xAI, Microsoft AI, NVIDIA, Hugging Face, Cohere,
   HN Algolia queries, r/MachineLearning, r/LocalLLaMA, simonwillison.net).
   Use real, current public feed URLs — verify format plausibility; prefer `/rss`/`/feed.xml`
   well-known paths (openai.com/blog/rss, anthropic.com/rss, etc.) — when unsure use the
   site's known feed or mark with a TODO comment.
4. `FeedParsing.swift`: minimal RSS 2.0 + Atom + JSON (Algolia) parsers using XMLParser /
   JSONDecoder. Handle date formats (RFC822, ISO8601, HN unix timestamps). Malformed item →
   skip item, never crash.
5. `FeedFetching.swift`: `protocol FeedFetching { func fetch(_ source: Source) async throws -> [NewsItem] }`
   + `URLSessionFeedFetcher` implementation. Errors typed (`FeedError`).
6. `JevClassifier.swift`: the typesafe classifier per contract. Pure Swift, deterministic:
   typed `Topic` enum, `ClassificationScore { relevance, value, topics }`,
   keyword tables as static data, recency decay function, engagement normalization.
   Fast: no regex backtracking pathologies; simple contains-based matching over typed rules.
7. `PulseModel.swift`: `@Observable` orchestration — fetch all sources concurrently
   (TaskGroup), classify, dedupe (by URL + normalized title), sort. MUST use a request-id
   guard: bump `generation` on every refresh; discard results whose generation is stale.
   Cache last successful result in memory + JSON snapshot on disk for offline display with
   a `isStale` flag.
8. `SavedStore.swift`: protocol + SwiftData-backed saved-items store (also an in-memory
   impl for tests). Save/remove/list.

## Step 3 — UI (`Sources/AIPulseUI`)

Minimalist design system (reuse/adapt template Theme): clean typography, SF Symbols,
light/dark, no clutter. Screens: Pulse (ranked), Latest (chronological + filters),
Topics (grouped + trending), Saved, Detail (summary + Read link via openURL).
TabView shell. Loading / empty / error+retry states everywhere. Relative time formatting.
Accessibility labels on interactive elements.

## Step 4 — Tests (`Tests/AIPulseCoreTests` etc.)

- Classifier: relevance/value scoring on representative fixtures (high-value model release,
  job ad → low, crypto spam → low, new OSS tool → high value + tooling topic); determinism
  (same input twice → same output); recency decay monotonic; engagement normalization.
- Parser: RSS, Atom, Algolia JSON, malformed-XML skip tests. Date parsing variants.
- PulseModel: request-id guard test (slow fetch A, refresh, fast fetch B returns → A's late
  result must NOT clobber B); dedupe test; offline cache test.
- SavedStore: add/remove/list round-trip (in-memory).
- UI: at least a smoke view test that Pulse list renders fixture items.
Provide typed fixtures inline in the tests. Target ≥ 40 meaningful assertions total.

## Step 5 — Verify

Run, in order, and fix everything until green:
1. `swift build`
2. `swift test`
3. `xcodegen generate`
4. `xcodebuild -project AIPulse.xcodeproj -scheme AIPulse -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build`
   (skip if no simulator runtime is available; record why)

## Constraints

- No new third-party dependencies. SwiftData/XMLParser/URLSession only.
- No API keys, no secrets, no signing values anywhere in the repo.
- No accounts, no tracking, no analytics.
- App display name: "AI Pulse". Deployment target iOS 17.0.
- Do NOT git commit — leave the working tree for review.
