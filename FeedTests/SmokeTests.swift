import XCTest
@testable import Feed

final class ModelDecodingTests: XCTestCase {
    func testFixturesDecode() throws {
        for cat in FeedCategory.allCases {
            let url = try XCTUnwrap(Bundle(for: FeedApp_Marker.self).url(forResource: "feed_\(cat.rawValue)", withExtension: "json") ?? Bundle.main.url(forResource: "feed_\(cat.rawValue)", withExtension: "json"))
            let page = try JSONDecoder.feed.decode(FeedPage.self, from: Data(contentsOf: url))
            if cat == .forYou { XCTAssertEqual(page.items.count, 12) }
            for post in page.items {
                XCTAssertFalse(post.media.isEmpty, "\(post.id) has media")
                XCTAssertFalse(post.products.isEmpty, "\(post.id) has products")
            }
        }
    }

    func testPostgresDates() {
        XCTAssertNotNil(PostgresDate.parse("2026-09-01T12:00:00.123456+00:00"))
        XCTAssertNotNil(PostgresDate.parse("2026-09-01T12:00:00Z"))
        XCTAssertNotNil(PostgresDate.parse("2026-09-01 12:00:00.1+00"))
        XCTAssertNotNil(PostgresDate.parse("2026-09-01T12:00:00+00:00"))
        XCTAssertNil(PostgresDate.parse("nope"))
    }

    func testPriceFormatting() {
        XCTAssertEqual(PriceFormatter.string(cents: 12900, currency: "USD"), "$129")
        XCTAssertEqual(PriceFormatter.string(cents: 4850, currency: "USD"), "$48.50")
        XCTAssertNil(PriceFormatter.string(cents: nil, currency: "USD"))
        XCTAssertEqual(CountFormatter.compact(2200), "2.2K")
        XCTAssertEqual(CountFormatter.compact(15), "15")
        XCTAssertEqual(CountFormatter.compact(1_500_000), "1.5M")
    }
}

@MainActor
final class FeedStoreTests: XCTestCase {
    struct DupRepo: FeedRepository {
        func fetchFeed(category: FeedCategory, sessionId: UUID, cursor: String?, limit: Int) async throws -> FeedPage {
            let posts = MockFeedRepository.fixturePosts(for: .forYou)
            let page = Array(posts.prefix(4))
            // Second page repeats one post to exercise dedup.
            return cursor == nil
                ? FeedPage(requestId: "1", nextCursor: "2", items: page)
                : FeedPage(requestId: "2", nextCursor: nil, items: [page[3]] + Array(posts.dropFirst(4).prefix(3)))
        }
    }

    func testDedupAndPaging() async {
        let store = FeedStore(category: .forYou, repository: DupRepo(), sessionId: UUID(), pageSize: 4)
        await store.loadInitialIfNeeded()
        XCTAssertEqual(store.items.count, 4)
        XCTAssertEqual(store.currentPostID, store.items.first?.id)
        store.loadMoreIfNeeded(currentIndex: 3)
        try? await Task.sleep(for: .milliseconds(300))
        XCTAssertEqual(store.items.count, 7, "duplicate post should be dropped")
        XCTAssertFalse(store.hasMore)
    }
}

final class EventTrackerTests: XCTestCase {
    actor Sink: EventRepository {
        var batches: [[AnalyticsEvent]] = []
        func send(_ events: [AnalyticsEvent]) async throws { batches.append(events) }
    }

    func testFlushesAtBatchSize() async {
        let sink = Sink()
        let tracker = EventTracker(repository: sink, batchSize: 3, maxDelay: .seconds(30))
        let session = UUID()
        for _ in 0..<3 { await tracker.track(AnalyticsEvent(type: .view, sessionId: session)) }
        try? await Task.sleep(for: .milliseconds(200))
        let batches = await sink.batches
        XCTAssertEqual(batches.count, 1)
        XCTAssertEqual(batches.first?.count, 3)
    }

    func testFlushesOnTimer() async {
        let sink = Sink()
        let tracker = EventTracker(repository: sink, batchSize: 100, maxDelay: .milliseconds(100))
        await tracker.track(AnalyticsEvent(type: .like, sessionId: UUID()))
        try? await Task.sleep(for: .milliseconds(400))
        let batches = await sink.batches
        XCTAssertEqual(batches.count, 1)
    }
}

private final class FeedApp_Marker {}
