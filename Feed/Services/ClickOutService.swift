import Foundation

/// Builds the outbound URL for a product tap and records the click event.
@MainActor
final class ClickOutService {
    private let tracker: EventTracker
    private let sessionId: UUID
    private let redirectBase: URL?

    init(tracker: EventTracker, sessionId: UUID, redirectBase: URL?) {
        self.tracker = tracker
        self.sessionId = sessionId
        self.redirectBase = redirectBase
    }

    func url(for product: Product, in post: Post, position: Int?) -> URL {
        let clickId = UUID()
        Task {
            await tracker.track(AnalyticsEvent(type: .clickOut, sessionId: sessionId, postId: post.id, productId: product.id,
                                               authorId: post.author.id, category: post.category, position: position, clickId: clickId))
        }
        if let base = redirectBase, let rid = product.redirectId {
            return base.appending(path: rid).appending(queryItems: [URLQueryItem(name: "c", value: clickId.uuidString)])
        }
        return product.url
    }
}
