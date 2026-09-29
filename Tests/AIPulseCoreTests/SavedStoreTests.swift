import XCTest
@testable import AIPulseCore

@MainActor
final class SavedStoreTests: XCTestCase {
    func testInMemoryRoundTrip() throws {
        let store = InMemorySavedStore()
        let a = fixture("Story A", "https://a.example/1", source: .openai)
        let b = fixture("Story B", "https://b.example/2", source: .hackerNews)

        try store.save(a)
        try store.save(b)
        XCTAssertTrue(try store.contains(id: a.id))
        XCTAssertEqual(try store.list().count, 2)
        XCTAssertEqual(Set(try store.list().map(\.title)), ["Story A", "Story B"])

        try store.remove(id: a.id)
        XCTAssertFalse(try store.contains(id: a.id))
        XCTAssertEqual(try store.list().count, 1)
        XCTAssertEqual(try store.list().first?.title, "Story B")

        // Save same id twice is idempotent.
        try store.save(b)
        XCTAssertEqual(try store.list().count, 1)
    }

    func testSwiftDataInMemoryRoundTrip() throws {
        let store = try SwiftDataSavedStore(inMemory: true)
        let a = fixture("SwiftData A", "https://a.example/sd1", source: .anthropic)
        let b = fixture("SwiftData B", "https://b.example/sd2", source: .redditMachineLearning,
                        published: nil)
        try store.save(a)
        try store.save(b)
        XCTAssertTrue(try store.contains(id: a.id))
        XCTAssertEqual(try store.list().count, 2)
        let restored = try store.list().first { $0.id == a.id }
        XCTAssertEqual(restored?.title, "SwiftData A")
        XCTAssertEqual(restored?.source, .anthropic)
        XCTAssertEqual(restored?.url, a.url)

        try store.remove(id: a.id)
        XCTAssertFalse(try store.contains(id: a.id))
        XCTAssertEqual(try store.list().count, 1)
    }
}

import SwiftData
