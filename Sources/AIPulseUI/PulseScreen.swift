import SwiftUI
import AIPulseCore

/// Ranked feed: relevance-gated, sorted by value. Pull-to-refresh,
/// loading / empty / error+retry states.
struct PulseScreen: View {
    @Bindable var model: PulseModel

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Pulse")
                .refreshable { await model.refresh() }
        }
    }

    @ViewBuilder
    private var content: some View {
        if model.isLoading && model.items.isEmpty {
            ProgressView("Loading feeds…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityLabel("Loading AI Pulse feeds")
        } else if let error = model.lastError, model.items.isEmpty {
            ErrorRetryView(message: error) {
                Task { await model.refresh() }
            }
        } else if model.items.isEmpty {
            emptyState
        } else {
            list
        }
    }

    private var list: some View {
        List {
            if model.isStale {
                Label("Offline — showing cached items", systemImage: "wifi.slash")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Offline. Showing cached items from last refresh.")
            }
            ForEach(model.items) { item in
                NavigationLink(value: item) {
                    NewsRow(scored: item)
                }
            }
        }
        .listStyle(.plain)
        .navigationDestination(for: ScoredItem.self) { DetailScreen(scored: $0) }
    }

    private var emptyState: some View {
        ContentUnavailableView(
            "No stories yet",
            systemImage: "waveform",
            description: Text("Pull to refresh to fetch the latest AI news.")
        )
    }
}

struct ErrorRetryView: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("Couldn't load feeds", systemImage: "wifi.exclamationmark")
        } description: {
            Text(message)
        } actions: {
            Button("Retry") { retry() }
                .buttonStyle(.borderedProminent)
                .accessibilityLabel("Retry loading feeds")
        }
    }
}
