import SwiftUI
import AIPulseCore

/// UI-facing wrapper over a SavedStore: observable list + save/remove.
@MainActor
@Observable
final class SavedModel {
    private let store: any SavedStore
    private(set) var items: [NewsItem] = []
    private(set) var errorMessage: String?

    init(store: any SavedStore) {
        self.store = store
    }

    func reload() {
        do {
            items = try store.list()
            errorMessage = nil
        } catch {
            errorMessage = "Couldn't read saved items: \(error)"
        }
    }

    func save(_ scored: ScoredItem) {
        do {
            try store.save(scored.item)
            reload()
        } catch {
            errorMessage = "Couldn't save: \(error)"
        }
    }

    func remove(_ item: NewsItem) {
        do {
            try store.remove(id: item.id)
            reload()
        } catch {
            errorMessage = "Couldn't remove: \(error)"
        }
    }

    func isSaved(_ item: NewsItem) -> Bool {
        (try? store.contains(id: item.id)) ?? false
    }
}
