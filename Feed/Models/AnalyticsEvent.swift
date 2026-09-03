import Foundation

enum EventType: String, Codable, Sendable {
    case view            // one per post shown; carries dwell_ms
    case clickOut = "click_out"
    case hide
    case share
    case like, unlike, save, unsave, follow, unfollow, comment
    case videoComplete = "video_complete"
    case carouselSwipe = "carousel_swipe"
    case quizComplete = "quiz_complete"
}

/// One row in the `events` table. `id` is generated on the client so retries are idempotent.
struct AnalyticsEvent: Codable, Sendable, Identifiable, Hashable {
    let id: UUID
    let type: EventType
    let occurredAt: Date
    let sessionId: UUID
    var postId: UUID? = nil
    var productId: UUID? = nil
    var authorId: UUID? = nil
    var category: String? = nil
    var position: Int? = nil
    var dwellMs: Int? = nil
    var mediaIndex: Int? = nil
    var clickId: UUID? = nil
    var payload: [String: String]? = nil

    init(type: EventType, sessionId: UUID, postId: UUID? = nil, productId: UUID? = nil, authorId: UUID? = nil, category: String? = nil, position: Int? = nil, dwellMs: Int? = nil, mediaIndex: Int? = nil, clickId: UUID? = nil, payload: [String: String]? = nil) {
        self.id = UUID(); self.type = type; self.occurredAt = Date(); self.sessionId = sessionId
        self.postId = postId; self.productId = productId; self.authorId = authorId; self.category = category
        self.position = position; self.dwellMs = dwellMs; self.mediaIndex = mediaIndex; self.clickId = clickId; self.payload = payload
    }
}
