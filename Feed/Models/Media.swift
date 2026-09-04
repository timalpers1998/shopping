import Foundation

enum MediaType: String, Codable, Sendable { case image, video }

struct Media: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let type: MediaType
    let url: URL
    let thumbnailUrl: URL?
    let width: Int
    let height: Int
    let durationSeconds: Double?
    let position: Int

    var aspectRatio: CGFloat { CGFloat(width) / CGFloat(max(height, 1)) }
    var isPortrait: Bool { aspectRatio < 0.8 }

    enum CodingKeys: String, CodingKey { case id, type, url, thumbnailUrl, width, height, durationSeconds, position }

    init(id: UUID, type: MediaType, url: URL, thumbnailUrl: URL?, width: Int, height: Int, durationSeconds: Double?, position: Int) {
        self.id = id; self.type = type; self.url = url; self.thumbnailUrl = thumbnailUrl
        self.width = width; self.height = height; self.durationSeconds = durationSeconds; self.position = position
    }

    /// Ingested catalog media often has no dimensions; assume portrait product photos.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        type = try c.decodeIfPresent(MediaType.self, forKey: .type) ?? .image
        url = try c.decode(URL.self, forKey: .url)
        thumbnailUrl = try c.decodeIfPresent(URL.self, forKey: .thumbnailUrl)
        width = try c.decodeIfPresent(Int.self, forKey: .width) ?? 1080
        height = try c.decodeIfPresent(Int.self, forKey: .height) ?? 1350
        durationSeconds = try c.decodeIfPresent(Double.self, forKey: .durationSeconds)
        position = try c.decodeIfPresent(Int.self, forKey: .position) ?? 0
    }
}
