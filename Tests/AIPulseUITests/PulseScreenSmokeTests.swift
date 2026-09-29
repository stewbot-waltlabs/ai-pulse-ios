import XCTest
import SwiftUI
@testable import AIPulseUI
@testable import AIPulseCore

/// Smoke tests: fixture data flows through the classifier into PulseModel and
/// the screens' view bodies build without trapping.
final class PulseScreenSmokeTests: XCTestCase {
    struct FixtureFetcher: FeedFetching {
        func fetch(_ source: Source) async throws -> [NewsItem] {
            [
                NewsItem(title: "Announcing a new open-source LLM toolkit on GitHub",
                         summary: "Library for GGUF inference and fine-tuning.",
                         url: URL(string: "https://example.com/toolkit")!,
                         source: .simonwillison,
                         publishedAt: Date(timeIntervalSince1970: 1_790_000_000),
                         engagement: NewsItem.Engagement(points: 210, comments: 40)),
                NewsItem(title: "Why large language models matter",
                         summary: "An opinion essay on AI.",
                         url: URL(string: "https://example.com/why")!,
                         source: .openai,
                         publishedAt: Date(timeIntervalSince1970: 1_790_001_000)),
            ]
        }
    }

    @MainActor
    private func makePopulatedModel() async -> (PulseModel, AppModel) {
        let appModel = AppModel(fetcher: FixtureFetcher(), cacheURL: nil)
        await appModel.pulse.refresh()
        return (appModel.pulse, appModel)
    }

    @MainActor
    func testPulseListRendersFixtureItems() async {
        let (model, appModel) = await makePopulatedModel()
        XCTAssertEqual(model.items.count, 2, "relevant fixtures survive the classifier")
        XCTAssertEqual(Set(model.items.map({ $0.item.source })), [.simonwillison, .openai])
        let values = model.items.map({ $0.score.value })
        XCTAssertEqual(values, values.sorted(by: >), "Pulse list must be ranked by value descending")

        let screen = PulseScreen(model: model).environment(appModel)
        XCTAssertNotNil(hostingView(for: screen), "Pulse body must build")
    }

    @MainActor
    func testOtherScreensBuild() async {
        let (model, appModel) = await makePopulatedModel()
        XCTAssertNotNil(hostingView(for: LatestScreen(model: model).environment(appModel)))
        XCTAssertNotNil(hostingView(for: TopicsScreen(model: model).environment(appModel)))
        XCTAssertNotNil(hostingView(for: RootView().environment(appModel)))
        let savedModel = SavedModel(store: InMemorySavedStore())
        savedModel.save(model.items[0])
        XCTAssertFalse(savedModel.items.isEmpty)
    }

    /// Error-state coverage: total fetch failure must expose lastError with no
    /// items, and Latest/Topics must build their error+retry branches.
    struct FailingFetcher: FeedFetching {
        func fetch(_ source: Source) async throws -> [NewsItem] {
            throw FeedError.network("offline")
        }
    }

    @MainActor
    func testLatestAndTopicsScreensBuildInErrorState() async {
        let appModel = AppModel(fetcher: FailingFetcher(), cacheURL: nil)
        await appModel.pulse.refresh()
        XCTAssertNotNil(appModel.pulse.lastError, "total failure must surface an error")
        XCTAssertTrue(appModel.pulse.items.isEmpty)
        XCTAssertNotNil(hostingView(for: LatestScreen(model: appModel.pulse).environment(appModel)),
                        "Latest error branch must build")
        XCTAssertNotNil(hostingView(for: TopicsScreen(model: appModel.pulse).environment(appModel)),
                        "Topics error branch must build")
    }

    /// Forces body evaluation by hosting the view; returns the platform view.
    @MainActor
    private func hostingView<V: View>(for view: V) -> NSView? {
        #if canImport(UIKit)
        return UIHostingController(rootView: view).view
        #elseif canImport(AppKit)
        return NSHostingController(rootView: view).view
        #else
        return nil
        #endif
    }
}

#if canImport(AppKit)
import AppKit
#endif
#if canImport(UIKit)
import UIKit
#endif
