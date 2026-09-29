import SwiftUI
import AIPulseCore

/// Grouped by topic; "trending" = highest count of recent items.
struct TopicsScreen: View {
    @Bindable var model: PulseModel

    private var grouped: [(topic: Topic, items: [ScoredItem])] {
        var buckets: [Topic: [ScoredItem]] = [:]
        for scored in model.items {
            for topic in scored.score.topics {
                buckets[topic, default: []].append(scored)
            }
        }
        // Trending: more items → higher; tie-break by topic name for determinism.
        return buckets
            .map { (topic: $0.key, items: $0.value.sorted { $0.score.value > $1.score.value }) }
            .sorted {
                if $0.items.count != $1.items.count { return $0.items.count > $1.items.count }
                return $0.topic.rawValue < $1.topic.rawValue
            }
    }

    var body: some View {
        NavigationStack {
            Group {
                if model.isLoading && model.items.isEmpty {
                    ProgressView("Loading feeds…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .accessibilityLabel("Loading AI Pulse feeds")
                } else if let error = model.lastError, model.items.isEmpty {
                    ErrorRetryView(message: error) {
                        Task { await model.refresh() }
                    }
                } else if grouped.isEmpty {
                    ContentUnavailableView("No topics yet", systemImage: "square.grid.2x2",
                                           description: Text("Refresh to classify incoming stories."))
                } else {
                    List {
                        ForEach(grouped, id: \.topic) { group in
                            Section {
                                ForEach(group.items) { item in
                                    NavigationLink(value: item) { NewsRow(scored: item) }
                                }
                            } header: {
                                HStack {
                                    Text(group.topic.displayName)
                                    Spacer()
                                    Text(verbatim: trendingLabel(group))
                                        .font(.caption2.weight(.bold))
                                        .foregroundStyle(Color.accentColor)
                                        .accessibilityLabel("\(group.topic.displayName) is trending with \(group.items.count) stories")
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Topics")
            .navigationDestination(for: ScoredItem.self) { DetailScreen(scored: $0) }
        }
    }

    private func trendingLabel(_ group: (topic: Topic, items: [ScoredItem])) -> String {
        if isTrending(group) { return "Trending" }
        return "\(group.items.count) stories"
    }

    private var trendingThreshold: Int {
        max(grouped.map(\.items.count).max() ?? 0, 1)
    }

    private func isTrending(_ group: (topic: Topic, items: [ScoredItem])) -> Bool {
        group.items.count == trendingThreshold && group.items.count >= 3
    }
}
