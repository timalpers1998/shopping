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
}
