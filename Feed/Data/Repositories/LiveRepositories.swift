import Foundation
import Supabase

struct LiveFeedRepository: FeedRepository {
    let client: SupabaseClient

    private struct Params: Encodable {
        let pCategory: String
        let pSessionId: UUID
        let pCursor: String?
        let pLimit: Int
    }

    func fetchFeed(category: FeedCategory, sessionId: UUID, cursor: String?, limit: Int) async throws -> FeedPage {
        try await client.rpc("get_feed", params: Params(pCategory: category.rawValue, pSessionId: sessionId, pCursor: cursor, pLimit: limit))
            .execute().value
    }
}

struct LiveEventRepository: EventRepository {
    let client: SupabaseClient

    private struct Params: Encodable { let pEvents: [AnalyticsEvent] }

    func send(_ events: [AnalyticsEvent]) async throws {
        let _: Int = try await client.rpc("record_events", params: Params(pEvents: events)).execute().value
    }
}

struct ToggleResult: Decodable, Sendable {
    let active: Bool
    let count: Int
}

protocol SocialRepository: Sendable {
    func toggleLike(postId: UUID) async throws -> ToggleResult
    func toggleSave(postId: UUID) async throws -> ToggleResult
    func toggleFollow(authorId: UUID) async throws -> ToggleResult
}

struct LiveSocialRepository: SocialRepository {
    let client: SupabaseClient
    private struct PostParams: Encodable { let pPostId: UUID }
    private struct AuthorParams: Encodable { let pAuthorId: UUID }

    func toggleLike(postId: UUID) async throws -> ToggleResult {
        try await client.rpc("toggle_like", params: PostParams(pPostId: postId)).execute().value
    }
    func toggleSave(postId: UUID) async throws -> ToggleResult {
        try await client.rpc("toggle_save", params: PostParams(pPostId: postId)).execute().value
    }
    func toggleFollow(authorId: UUID) async throws -> ToggleResult {
        try await client.rpc("toggle_follow", params: AuthorParams(pAuthorId: authorId)).execute().value
    }
}

struct MockSocialRepository: SocialRepository {
    func toggleLike(postId: UUID) async throws -> ToggleResult { ToggleResult(active: true, count: 0) }
    func toggleSave(postId: UUID) async throws -> ToggleResult { ToggleResult(active: true, count: 0) }
    func toggleFollow(authorId: UUID) async throws -> ToggleResult { ToggleResult(active: true, count: 0) }
}
