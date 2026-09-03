import Foundation

enum PostKind: String, Codable, Sendable { case image, carousel, video }

struct PostStats: Codable, Hashable, Sendable {
    var likes: Int
    var comments: Int
    var saves: Int
    static let zero = PostStats(likes: 0, comments: 0, saves: 0)
}

struct ViewerState: Codable, Hashable, Sendable {
    var liked: Bool
    var saved: Bool
    static let none = ViewerState(liked: false, saved: false)
}

struct Post: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let kind: PostKind
    let caption: String
    let createdAt: Date
    let category: String
    let styleTags: [String]
    let rankScore: Double?
    var author: Author
    let media: [Media]
    let products: [Product]
    var stats: PostStats
    var viewer: ViewerState

    var coverURL: URL? { media.first?.thumbnailUrl ?? media.first?.url }

    enum CodingKeys: String, CodingKey {
        case id, kind, caption, createdAt, category, styleTags, rankScore, author, media, products, stats, viewer
    }

    init(id: UUID, kind: PostKind, caption: String, createdAt: Date, category: String, styleTags: [String] = [], rankScore: Double? = nil, author: Author, media: [Media], products: [Product], stats: PostStats = .zero, viewer: ViewerState = .none) {
        self.id = id; self.kind = kind; self.caption = caption; self.createdAt = createdAt; self.category = category
        self.styleTags = styleTags; self.rankScore = rankScore; self.author = author; self.media = media
        self.products = products; self.stats = stats; self.viewer = viewer
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        kind = try c.decode(PostKind.self, forKey: .kind)
        caption = try c.decodeIfPresent(String.self, forKey: .caption) ?? ""
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        category = try c.decodeIfPresent(String.self, forKey: .category) ?? "fashion"
        styleTags = try c.decodeIfPresent([String].self, forKey: .styleTags) ?? []
        rankScore = try c.decodeIfPresent(Double.self, forKey: .rankScore)
        author = try c.decode(Author.self, forKey: .author)
        media = try c.decodeIfPresent([Media].self, forKey: .media) ?? []
        products = try c.decodeIfPresent([Product].self, forKey: .products) ?? []
        stats = try c.decodeIfPresent(PostStats.self, forKey: .stats) ?? .zero
        viewer = try c.decodeIfPresent(ViewerState.self, forKey: .viewer) ?? .none
    }
}

struct FeedPage: Codable, Sendable {
    let requestId: String
    let nextCursor: String?
    let items: [Post]
}
