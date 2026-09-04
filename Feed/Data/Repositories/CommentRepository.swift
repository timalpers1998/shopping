import Foundation
import Supabase

struct CommentPage: Codable, Sendable {
    let items: [Comment]
    let nextCursor: String?
}

protocol CommentRepository: Sendable {
    func comments(postId: UUID, cursor: String?) async throws -> CommentPage
    func add(postId: UUID, text: String) async throws -> Comment
    func delete(commentId: UUID) async throws
}

struct LiveCommentRepository: CommentRepository {
    let client: SupabaseClient
    private struct ListParams: Encodable { let pPostId: UUID; let pCursor: String?; let pLimit: Int }
    private struct AddParams: Encodable { let pPostId: UUID; let pBody: String }
    private struct DeleteParams: Encodable { let pCommentId: UUID }

    func comments(postId: UUID, cursor: String?) async throws -> CommentPage {
        try await client.rpc("get_comments", params: ListParams(pPostId: postId, pCursor: cursor, pLimit: 30)).execute().value
    }
    func add(postId: UUID, text: String) async throws -> Comment {
        try await client.rpc("add_comment", params: AddParams(pPostId: postId, pBody: text)).execute().value
    }
    func delete(commentId: UUID) async throws {
        try await client.rpc("delete_comment", params: DeleteParams(pCommentId: commentId)).execute()
    }
}

/// In-memory comments for fixtures.
actor MockCommentStore {
    static let shared = MockCommentStore()
    private var byPost: [UUID: [Comment]] = [:]
    func list(_ postId: UUID) -> [Comment] {
        if byPost[postId] == nil {
            let author = Author(id: UUID(), handle: "june.wardrobe", displayName: "June", avatarUrl: URL(string: "https://picsum.photos/seed/avatar-june.wardrobe/200/200"), kind: .creator, isVerified: true)
            byPost[postId] = [Comment(id: UUID(), postId: postId, author: author, text: "need this immediately 😭", createdAt: Date().addingTimeInterval(-3600))]
        }
        return byPost[postId] ?? []
    }
    func add(_ c: Comment) { byPost[c.postId, default: []].append(c) }
    func remove(_ id: UUID) { for k in byPost.keys { byPost[k]?.removeAll { $0.id == id } } }
}

struct MockCommentRepository: CommentRepository {
    func comments(postId: UUID, cursor: String?) async throws -> CommentPage {
        CommentPage(items: await MockCommentStore.shared.list(postId), nextCursor: nil)
    }
    func add(postId: UUID, text: String) async throws -> Comment {
        let c = Comment(id: UUID(), postId: postId, author: Author(id: UUID(), handle: "you", displayName: "You", kind: .creator), text: text, createdAt: Date())
        await MockCommentStore.shared.add(c)
        return c
    }
    func delete(commentId: UUID) async throws { await MockCommentStore.shared.remove(commentId) }
}
