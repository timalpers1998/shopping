import Foundation
import Supabase

protocol ProfileRepository: Sendable {
    func me() async throws -> Me?
    func authorProfile(id: UUID) async throws -> AuthorProfile
    func authorPosts(id: UUID, cursor: String?) async throws -> PostPage
    func savedPosts(cursor: String?) async throws -> PostPage
    func createCreatorAuthor(handle: String, displayName: String) async throws -> Author
}

struct LiveProfileRepository: ProfileRepository {
    let client: SupabaseClient
    private struct AuthorParams: Encodable { let pAuthorId: UUID }
    private struct AuthorPostsParams: Encodable { let pAuthorId: UUID; let pCursor: String?; let pLimit: Int }
    private struct SavedParams: Encodable { let pCursor: String?; let pLimit: Int }
    private struct CreateAuthorParams: Encodable { let pHandle: String; let pDisplayName: String }

    func me() async throws -> Me? {
        try await client.rpc("get_me").execute().value
    }
    func authorProfile(id: UUID) async throws -> AuthorProfile {
        try await client.rpc("get_author_profile", params: AuthorParams(pAuthorId: id)).execute().value
    }
    func authorPosts(id: UUID, cursor: String?) async throws -> PostPage {
        try await client.rpc("get_author_posts", params: AuthorPostsParams(pAuthorId: id, pCursor: cursor, pLimit: 18)).execute().value
    }
    func savedPosts(cursor: String?) async throws -> PostPage {
        try await client.rpc("get_saved_posts", params: SavedParams(pCursor: cursor, pLimit: 18)).execute().value
    }
    func createCreatorAuthor(handle: String, displayName: String) async throws -> Author {
        try await client.rpc("create_creator_author", params: CreateAuthorParams(pHandle: handle, pDisplayName: displayName)).execute().value
    }
}

/// Fixture-backed profile data for previews, UI tests and offline work.
struct MockProfileRepository: ProfileRepository {
    func me() async throws -> Me? {
        Me(id: UUID(uuidString: "00000000-0000-4000-a000-000000000001")!, username: "you", displayName: "You", avatarUrl: nil,
           isAnonymous: true, onboarded: false, audience: nil, priceBand: nil, followingCount: 0, authors: [])
    }
    func authorProfile(id: UUID) async throws -> AuthorProfile {
        let all = MockFeedRepository.fixturePosts(for: .forYou)
        let posts = all.filter { $0.author.id == id }
        guard let author = posts.first?.author ?? all.first?.author else { throw URLError(.fileDoesNotExist) }
        var a = author
        a.followerCount = 12_400; a.postCount = posts.count; a.bio = "fits, finds, and the occasional splurge."
        return AuthorProfile(author: a, posts: posts, nextCursor: nil)
    }
    func authorPosts(id: UUID, cursor: String?) async throws -> PostPage { PostPage(items: [], nextCursor: nil) }
    func savedPosts(cursor: String?) async throws -> PostPage {
        PostPage(items: Array(MockFeedRepository.fixturePosts(for: .forYou).filter { $0.viewer.saved }), nextCursor: nil)
    }
    func createCreatorAuthor(handle: String, displayName: String) async throws -> Author {
        Author(id: UUID(), handle: handle, displayName: displayName, kind: .creator)
    }
}
