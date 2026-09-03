import Foundation

protocol FeedRepository: Sendable {
    func fetchFeed(category: FeedCategory, sessionId: UUID, cursor: String?, limit: Int) async throws -> FeedPage
}

protocol EventRepository: Sendable {
    func send(_ events: [AnalyticsEvent]) async throws
}
