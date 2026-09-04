import Foundation

/// Serves posts from bundled fixture JSON with fake cursor paging. Used before the backend exists and in previews/tests.
struct MockFeedRepository: FeedRepository {
    var pageSize = 6
    var delay: Duration = .milliseconds(250)

    func fetchFeed(category: FeedCategory, sessionId: UUID, cursor: String?, limit: Int) async throws -> FeedPage {
        try? await Task.sleep(for: delay)
        let all = Self.fixturePosts(for: category)
        let offset = Int(cursor ?? "0") ?? 0
        let slice = Array(all.dropFirst(offset).prefix(limit))
        let next = offset + slice.count
        return FeedPage(requestId: "mock-\(category.rawValue)-\(offset)", nextCursor: next < all.count ? String(next) : nil, items: slice)
    }

    static func fixturePosts(for category: FeedCategory) -> [Post] {
        let name = "feed_\(category.rawValue)"
        guard let url = Bundle.main.url(forResource: name, withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let page = try? JSONDecoder.feed.decode(FeedPage.self, from: data) else { return [] }
        return page.items
    }
}

struct MockEventRepository: EventRepository {
    func send(_ events: [AnalyticsEvent]) async throws {
        for e in events {
            var parts = ["[event] \(e.type.rawValue)"]
            if let p = e.postId { parts.append("post=\(p.uuidString.prefix(8))") }
            if let d = e.dwellMs { parts.append("dwell=\(d)ms") }
            if let pos = e.position { parts.append("pos=\(pos)") }
            if let c = e.category { parts.append("cat=\(c)") }
            print(parts.joined(separator: " "))
        }
    }
}

/// Serves a fixed list (used by the post pager).
struct StaticFeedRepository: FeedRepository {
    let posts: [Post]
    func fetchFeed(category: FeedCategory, sessionId: UUID, cursor: String?, limit: Int) async throws -> FeedPage {
        FeedPage(requestId: "static", nextCursor: nil, items: posts)
    }
}
