import Foundation
import UIKit

struct ComposeMediaItem: Identifiable, Sendable {
    enum Kind: Sendable { case image, video }
    let id = UUID()
    let kind: Kind
    var preview: UIImage?
    var jpeg: Data?          // 1440px long edge
    var thumb: Data?         // 400px
    var width: Int
    var height: Int
    var videoURL: URL?       // exported MP4
    var poster: Data?        // video poster JPEG
    var durationMs: Int?
}

struct ProductDraft: Identifiable, Sendable, Equatable {
    enum Status: Sendable, Equatable { case scraping, ready, manual }
    let id = UUID()
    var url: String
    var status: Status = .scraping
    var title = ""
    var imageUrl: String?
    var priceCents: Int?
    var currency = "USD"
    var merchant = ""
    var brand: String?
    var isValid: Bool { !title.trimmingCharacters(in: .whitespaces).isEmpty && URL(string: url) != nil }
}

struct ComposeDraft: Sendable {
    var media: [ComposeMediaItem] = []
    var caption = ""
    var products: [ProductDraft] = []
    var category = "fashion"
    var audience = "unisex"
    var styleTags: [String] = []

    var kind: PostKind {
        if media.first?.kind == .video { return .video }
        return media.count > 1 ? .carousel : .image
    }
    var canPublish: Bool { !media.isEmpty && products.contains(where: \.isValid) && !products.contains(where: { $0.status == .scraping }) }
}

struct ScrapedProduct: Codable, Sendable {
    let ok: Bool?
    let canonicalUrl: String?
    let merchant: String?
    let brand: String?
    let title: String?
    let imageUrl: String?
    let priceCents: Int?
    let currency: String?
    let missing: [String]?
}
