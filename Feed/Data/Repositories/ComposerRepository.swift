import Foundation
import Supabase

protocol ScrapeRepository: Sendable {
    func scrape(url: String) async throws -> ScrapedProduct
}

struct LiveScrapeRepository: ScrapeRepository {
    let client: SupabaseClient
    private struct Body: Encodable { let url: String }
    func scrape(url: String) async throws -> ScrapedProduct {
        try await client.functions.invoke("scrape-product", options: .init(body: Body(url: url)), decode: { data, _ in
            try JSONDecoder.feed.decode(ScrapedProduct.self, from: data)
        })
    }
}

struct MockScrapeRepository: ScrapeRepository {
    func scrape(url: String) async throws -> ScrapedProduct {
        try? await Task.sleep(for: .milliseconds(600))
        let host = URL(string: url)?.host()?.replacingOccurrences(of: "www.", with: "") ?? "store.com"
        return ScrapedProduct(ok: true, canonicalUrl: url, merchant: host, brand: host.split(separator: ".").first.map { $0.capitalized },
                              title: "Scraped item from \(host)", imageUrl: "https://picsum.photos/seed/\(host)/600/800", priceCents: 4900, currency: "USD", missing: [])
    }
}

protocol ComposerRepository: Sendable {
    /// Uploads media and creates the post. `progress` is 0...1.
    func publish(_ draft: ComposeDraft, author: Author, progress: @Sendable @escaping (Double) -> Void) async throws -> Post
}

struct LiveComposerRepository: ComposerRepository {
    let client: SupabaseClient

    private struct MediaPayload: Encodable { let position: Int; let kind: String; let storagePath: String; let width: Int; let height: Int; let durationMs: Int?; let thumbnailPath: String? }
    private struct ProductPayload: Encodable { let position: Int; let title: String; let url: String; let imageUrl: String?; let priceCents: Int?; let currency: String; let merchant: String; let brand: String? }
    private struct PostPayload: Encodable {
        let id: UUID; let authorId: UUID; let kind: String; let caption: String; let category: String; let audience: String
        let styleTags: [String]; let media: [MediaPayload]; let products: [ProductPayload]
    }
    private struct Params: Encodable { let p: PostPayload }

    func publish(_ draft: ComposeDraft, author: Author, progress: @Sendable @escaping (Double) -> Void) async throws -> Post {
        let postId = UUID()
        let bucket = client.storage.from("media")
        let base = "\(author.id.uuidString.lowercased())/\(postId.uuidString.lowercased())"
        var media: [MediaPayload] = []
        let total = Double(draft.media.count) + 1
        for (i, item) in draft.media.enumerated() {
            switch item.kind {
            case .image:
                guard let jpeg = item.jpeg else { continue }
                try await bucket.upload("\(base)/\(i).jpg", data: jpeg, options: FileOptions(cacheControl: "31536000", contentType: "image/jpeg", upsert: true))
                var thumbPath: String? = nil
                if let thumb = item.thumb {
                    try await bucket.upload("\(base)/\(i)_thumb.jpg", data: thumb, options: FileOptions(cacheControl: "31536000", contentType: "image/jpeg", upsert: true))
                    thumbPath = "\(base)/\(i)_thumb.jpg"
                }
                media.append(MediaPayload(position: i, kind: "image", storagePath: "\(base)/\(i).jpg", width: item.width, height: item.height, durationMs: nil, thumbnailPath: thumbPath))
            case .video:
                guard let url = item.videoURL else { continue }
                let data = try Data(contentsOf: url)
                try await bucket.upload("\(base)/\(i).mp4", data: data, options: FileOptions(cacheControl: "31536000", contentType: "video/mp4", upsert: true))
                var posterPath: String? = nil
                if let poster = item.poster {
                    try await bucket.upload("\(base)/\(i)_poster.jpg", data: poster, options: FileOptions(cacheControl: "31536000", contentType: "image/jpeg", upsert: true))
                    posterPath = "\(base)/\(i)_poster.jpg"
                }
                media.append(MediaPayload(position: i, kind: "video", storagePath: "\(base)/\(i).mp4", width: item.width, height: item.height, durationMs: item.durationMs, thumbnailPath: posterPath))
            }
            progress(Double(i + 1) / total)
        }
        let products = draft.products.filter(\.isValid).enumerated().map { i, p in
            ProductPayload(position: i, title: p.title, url: p.url, imageUrl: p.imageUrl, priceCents: p.priceCents, currency: p.currency, merchant: p.merchant, brand: p.brand)
        }
        let payload = PostPayload(id: postId, authorId: author.id, kind: draft.kind.rawValue, caption: draft.caption, category: draft.category,
                                  audience: draft.audience, styleTags: draft.styleTags, media: media, products: products)
        let post: Post = try await client.rpc("create_post", params: Params(p: payload)).execute().value
        progress(1)
        return post
    }
}

struct MockComposerRepository: ComposerRepository {
    func publish(_ draft: ComposeDraft, author: Author, progress: @Sendable @escaping (Double) -> Void) async throws -> Post {
        for i in 1...4 { try? await Task.sleep(for: .milliseconds(200)); progress(Double(i) / 4) }
        let media = draft.media.enumerated().map { i, m in
            Media(id: UUID(), type: m.kind == .video ? .video : .image, url: URL(string: "https://picsum.photos/seed/new-\(i)/1080/1440")!, thumbnailUrl: nil, width: m.width, height: m.height, durationSeconds: m.durationMs.map { Double($0) / 1000 }, position: i)
        }
        let products = draft.products.filter(\.isValid).enumerated().map { i, p in
            Product(id: UUID(), title: p.title, imageUrl: p.imageUrl.flatMap(URL.init(string:)), priceCents: p.priceCents, currency: p.currency, merchant: p.merchant, brand: p.brand, url: URL(string: p.url)!, position: i)
        }
        return Post(id: UUID(), kind: draft.kind, caption: draft.caption, createdAt: Date(), category: draft.category, styleTags: draft.styleTags, author: author, media: media, products: products)
    }
}
