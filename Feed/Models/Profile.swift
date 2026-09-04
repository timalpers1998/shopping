import Foundation

/// The signed-in (or anonymous) user's own profile.
struct Me: Codable, Sendable, Equatable {
    let id: UUID
    var username: String?
    var displayName: String?
    var avatarUrl: URL?
    let isAnonymous: Bool
    let onboarded: Bool
    var audience: String?
    var priceBand: String?
    var followingCount: Int
    var authors: [Author]

    var primaryAuthor: Author? { authors.first }
}

struct AuthorProfile: Codable, Sendable {
    var author: Author
    var posts: [Post]
    var nextCursor: String?
}

struct PostPage: Codable, Sendable {
    let items: [Post]
    let nextCursor: String?
}
