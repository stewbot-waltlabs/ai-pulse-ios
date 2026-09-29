import SwiftUI
import AIPulseCore

/// Chronological feed with source and topic filters.
struct LatestScreen: View {
    @Bindable var model: PulseModel
    @State private var sourceFilter: Source?
    @State private var topicFilter: Topic?

    private var chronological: [ScoredItem] {
        model.items.sorted {
            ($0.item.publishedAt ?? .distantPast) > ($1.item.publishedAt ?? .distantPast)
        }
    }

    private var filtered: [ScoredItem] {
        chronological.filter { scored in
            if let sourceFilter, scored.item.source != sourceFilter { return false }
            if let topicFilter, !scored.score.topics.contains(topicFilter) { return false }
            return true
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
                } else {
                    list
                }
            }
            .navigationTitle("Latest")
            .navigationDestination(for: ScoredItem.self) { DetailScreen(scored: $0) }
        }
    }

    private var list: some View {
        List {
            Section {
                ForEach(filtered) { item in
                    NavigationLink(value: item) { NewsRow(scored: item) }
                }
            } header: {
                filterHeader
            }
        }
        .listStyle(.plain)
        .overlay {
            if filtered.isEmpty { emptyState }
        }
    }

    private var filterHeader: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Menu {
                    Button("All sources") { sourceFilter = nil }
                    ForEach(Source.allCases) { source in
                        Button(source.displayName) { sourceFilter = source }
                    }
                } label: {
                    Label(sourceFilter?.displayName ?? "All sources", systemImage: "line.3.horizontal.decrease.circle")
                        .font(.caption)
                }
                .accessibilityLabel("Filter by source, currently \(sourceFilter?.displayName ?? "all sources")")

                Menu {
                    Button("All topics") { topicFilter = nil }
                    ForEach(Topic.allCases) { topic in
                        Button(topic.displayName) { topicFilter = topic }
                    }
                } label: {
                    Label(topicFilter?.displayName ?? "All topics", systemImage: "tag")
                        .font(.caption)
                }
                .accessibilityLabel("Filter by topic, currently \(topicFilter?.displayName ?? "all topics")")
            }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView("Nothing here", systemImage: "clock", description: Text("No items match the current filters."))
    }
}
