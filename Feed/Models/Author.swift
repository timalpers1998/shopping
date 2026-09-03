import Foundation

enum AuthorKind: String, Codable, Sendable { case creator, brand }

struct Author: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let handle: String
    let displayName: String
    let avatarUrl: URL?
    let kind: AuthorKind
    var isVerified: Bool
    var isFollowing: Bool
    var followerCount: Int?
    var postCount: Int?
    var bio: String?

    init(id: UUID, handle: String, displayName: String, avatarUrl: URL? = nil, kind: AuthorKind, isVerified: Bool = false, isFollowing: Bool = false, followerCount: Int? = nil, postCount: Int? = nil, bio: String? = nil) {
        self.id = id; self.handle = handle; self.displayName = displayName; self.avatarUrl = avatarUrl
        self.kind = kind; self.isVerified = isVerified; self.isFollowing = isFollowing
        self.followerCount = followerCount; self.postCount = postCount; self.bio = bio
    }

    enum CodingKeys: String, CodingKey { case id, handle, displayName, avatarUrl, kind, isVerified, isFollowing, followerCount, postCount, bio }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        handle = try c.decode(String.self, forKey: .handle)
        displayName = try c.decodeIfPresent(String.self, forKey: .displayName) ?? handle
        avatarUrl = try c.decodeIfPresent(URL.self, forKey: .avatarUrl)
        kind = try c.decodeIfPresent(AuthorKind.self, forKey: .kind) ?? .creator
        isVerified = try c.decodeIfPresent(Bool.self, forKey: .isVerified) ?? false
        isFollowing = try c.decodeIfPresent(Bool.self, forKey: .isFollowing) ?? false
        followerCount = try c.decodeIfPresent(Int.self, forKey: .followerCount)
        postCount = try c.decodeIfPresent(Int.self, forKey: .postCount)
        bio = try c.decodeIfPresent(String.self, forKey: .bio)
    }
}
