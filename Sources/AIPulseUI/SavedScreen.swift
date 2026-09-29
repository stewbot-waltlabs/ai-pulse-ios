import SwiftUI
import AIPulseCore

/// Locally saved items. Swipe to remove, no account.
struct SavedScreen: View {
    @State private var model: SavedModel
    private let store: any SavedStore

    init(store: any SavedStore) {
        self.store = store
        _model = State(initialValue: SavedModel(store: store))
    }

    var body: some View {
        NavigationStack {
            Group {
                if let error = model.errorMessage, model.items.isEmpty {
                    ErrorRetryView(message: error) { model.reload() }
                } else if model.items.isEmpty {
                    ContentUnavailableView("Nothing saved", systemImage: "bookmark",
                                           description: Text("Save stories to read later. They stay on this device."))
                } else {
                    List {
                        ForEach(model.items) { item in
                            NavigationLink {
                                DetailScreen(scored: ScoredItem(item: item,
                                                                score: ClassificationScore(relevance: 1, value: 1, topics: [])))
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(item.title).font(Theme.title).lineLimit(3)
                                    HStack {
                                        SourceBadge(source: item.source)
                                        RelativeTimeText(date: item.publishedAt)
                                    }
                                }
                            }
                        }
                        .onDelete { indexSet in
                            let targets = indexSet.map { model.items[$0] }
                            for item in targets { model.remove(item) }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Saved")
            .task { model.reload() }
        }
    }
}
