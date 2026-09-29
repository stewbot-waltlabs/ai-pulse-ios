import Foundation

/// Saved items persistence. Protocol-first so tests use the in-memory store;
/// the app uses the SwiftData-backed store. MainActor-isolated because the
/// SwiftData implementation must live on the main actor.
@MainActor
public protocol SavedStore {
    func save(_ item: NewsItem) throws
    func remove(id: String) throws
    func list() throws -> [NewsItem]
    func contains(id: String) throws -> Bool
}

/// In-memory implementation for tests and previews.
public final class InMemorySavedStore: SavedStore {
    private var storage: [String: NewsItem] = [:]
    private var order: [String] = []

    public init() {}

    public func save(_ item: NewsItem) throws {
        if storage[item.id] == nil { order.append(item.id) }
        storage[item.id] = item
    }

    public func remove(id: String) throws {
        storage[id] = nil
        order.removeAll { $0 == id }
    }

    public func list() throws -> [NewsItem] {
        order.compactMap { storage[$0] }
    }

    public func contains(id: String) throws -> Bool {
        storage[id] != nil
    }
}

// MARK: - SwiftData store (app target; iOS 17+)

import SwiftData

/// SwiftData-backed store. Local only, no sync, no account.
@Model
public final class SavedItemRecord {
    @Attribute(.unique) public var itemID: String
    public var title: String
    public var summary: String
    public var urlString: String
    public var sourceRaw: String
    public var publishedAt: Date?
    public var points: Int?
    public var comments: Int?
    public var fetchedAt: Date
    public var savedAt: Date

    public init(item: NewsItem) {
        self.itemID = item.id
        self.title = item.title
        self.summary = item.summary
        self.urlString = item.url.absoluteString
        self.sourceRaw = item.source.rawValue
        self.publishedAt = item.publishedAt
        self.points = item.engagement?.points
        self.comments = item.engagement?.comments
        self.fetchedAt = item.fetchedAt
        self.savedAt = .now
    }

    public var newsItem: NewsItem? {
        guard let url = URL(string: urlString), let source = Source(rawValue: sourceRaw) else { return nil }
        var engagement: NewsItem.Engagement?
        if points != nil || comments != nil {
            engagement = NewsItem.Engagement(points: points, comments: comments)
        }
        return NewsItem(
            id: itemID,
            title: title,
            summary: summary,
            url: url,
            source: source,
            publishedAt: publishedAt,
            engagement: engagement,
            fetchedAt: fetchedAt
        )
    }
}

@MainActor
public final class SwiftDataSavedStore: SavedStore {
    private let container: ModelContainer

    public init(inMemory: Bool = false) throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: inMemory)
        container = try ModelContainer(for: SavedItemRecord.self, configurations: config)
    }

    public func save(_ item: NewsItem) throws {
        let context = ModelContext(container)
        if try contains(id: item.id, in: context) { return }
        context.insert(SavedItemRecord(item: item))
        try context.save()
    }

    public func remove(id: String) throws {
        let context = ModelContext(container)
        let all = try context.fetch(FetchDescriptor<SavedItemRecord>())
        for record in all where record.itemID == id { context.delete(record) }
        try context.save()
    }

    public func list() throws -> [NewsItem] {
        let context = ModelContext(container)
        let descriptor = FetchDescriptor<SavedItemRecord>(sortBy: [SortDescriptor(\.savedAt, order: .reverse)])
        return try context.fetch(descriptor).compactMap(\.newsItem)
    }

    public func contains(id: String) throws -> Bool {
        let context = ModelContext(container)
        return try contains(id: id, in: context)
    }

    private func contains(id: String, in context: ModelContext) throws -> Bool {
        var descriptor = FetchDescriptor<SavedItemRecord>(predicate: #Predicate { $0.itemID == id })
        descriptor.fetchLimit = 1
        return try !context.fetch(descriptor).isEmpty
    }
}
