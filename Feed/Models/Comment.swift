import Foundation

struct Comment: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let postId: UUID
    let author: Author
    var text: String
    let createdAt: Date
    var isPending: Bool = false

    enum CodingKeys: String, CodingKey { case id, postId, author, text, createdAt }
}
