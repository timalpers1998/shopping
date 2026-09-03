import Foundation

/// Tracks which post is on screen and for how long; emits one `view` event per post shown.
@MainActor
final class ImpressionTracker {
    private let tracker: EventTracker
    private let sessionId: UUID
    private var current: (post: Post, index: Int, category: FeedCategory, start: ContinuousClock.Instant)?
    private var maxMediaIndex = 0

    init(tracker: EventTracker, sessionId: UUID) {
        self.tracker = tracker
        self.sessionId = sessionId
    }

    func begin(post: Post, index: Int, category: FeedCategory) {
        end()
        current = (post, index, category, .now)
        maxMediaIndex = 0
    }

    func mediaShown(index: Int) { maxMediaIndex = max(maxMediaIndex, index) }

    func end() {
        guard let c = current else { return }
        current = nil
        let ms = Int((ContinuousClock.now - c.start) / .milliseconds(1))
        guard ms >= 100 else { return }
        let event = AnalyticsEvent(type: .view, sessionId: sessionId, postId: c.post.id, authorId: c.post.author.id,
                                   category: c.category.rawValue, position: c.index, dwellMs: ms, mediaIndex: maxMediaIndex)
        Task { await tracker.track(event) }
    }
}
