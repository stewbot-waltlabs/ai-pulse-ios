import SwiftUI
import AIPulseCore

/// TabView shell: Pulse / Latest / Topics / Saved.
public struct RootView: View {
    @State private var appModel = AppModel()

    public init() {}

    public var body: some View {
        TabView {
            PulseScreen(model: appModel.pulse)
                .tabItem { Label("Pulse", systemImage: "waveform") }
            LatestScreen(model: appModel.pulse)
                .tabItem { Label("Latest", systemImage: "clock") }
            TopicsScreen(model: appModel.pulse)
                .tabItem { Label("Topics", systemImage: "square.grid.2x2") }
            SavedScreen(store: appModel.saved)
                .tabItem { Label("Saved", systemImage: "bookmark") }
        }
        .task { appModel.start() }
        .environment(appModel)
    }
}

/// Wires the model graph. Injectable for tests/previews.
@Observable
@MainActor
public final class AppModel {
    let pulse: PulseModel
    let saved: any SavedStore
    let savedModel: SavedModel

    public init(
        fetcher: any FeedFetching = URLSessionFeedFetcher(),
        cacheURL: URL? = AppModel.defaultCacheURL
    ) {
        let pulse = PulseModel(fetcher: fetcher, cacheURL: cacheURL)
        let store: any SavedStore
        if let swiftData = try? SwiftDataSavedStore() {
            store = swiftData
        } else {
            store = InMemorySavedStore()
        }
        self.pulse = pulse
        self.saved = store
        self.savedModel = SavedModel(store: store)
    }

    public static var defaultCacheURL: URL? {
        URL.cachesDirectory.appending(path: "aipulse-snapshot.json")
    }

    public func start() {
        pulse.loadCachedIfAvailable()
        Task { await pulse.refresh() }
    }
}
