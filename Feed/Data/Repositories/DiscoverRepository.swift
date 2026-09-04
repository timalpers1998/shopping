import Foundation
import Supabase

struct TrendingProduct: Decodable, Sendable, Identifiable {
    let id: UUID
    let title: String
    let imageUrl: URL?
    let priceCents: Int?
    let currency: String
    let merchant: String
    let brand: String?
    let url: URL
    let postId: UUID?
    let redirectId: String?
}

protocol DiscoverRepository: Sendable {
    func search(_ query: String) async throws -> [Post]
    func trending() async throws -> [TrendingProduct]
}

struct LiveDiscoverRepository: DiscoverRepository {
    let client: SupabaseClient
    private struct SearchParams: Encodable { let pQuery: String; let pLimit: Int }
    private struct Wrapper: Decodable { let items: [Post] }
    private struct TrendingParams: Encodable { let pLimit: Int }

    func search(_ query: String) async throws -> [Post] {
        let w: Wrapper = try await client.rpc("search_posts", params: SearchParams(pQuery: query, pLimit: 30)).execute().value
        return w.items
    }
    func trending() async throws -> [TrendingProduct] {
        try await client.rpc("trending_products", params: TrendingParams(pLimit: 24)).execute().value
    }
}

struct MockDiscoverRepository: DiscoverRepository {
    func search(_ query: String) async throws -> [Post] {
        let q = query.lowercased()
        return MockFeedRepository.fixturePosts(for: .forYou).filter { p in
            p.caption.lowercased().contains(q) || p.styleTags.contains { $0.contains(q) } ||
            p.products.contains { $0.title.lowercased().contains(q) || ($0.brand ?? "").lowercased().contains(q) }
        }
    }
    func trending() async throws -> [TrendingProduct] {
        var seen = Set<UUID>()
        return MockFeedRepository.fixturePosts(for: .forYou).flatMap { post in
            post.products.compactMap { p in
                guard seen.insert(p.id).inserted else { return nil }
                return TrendingProduct(id: p.id, title: p.title, imageUrl: p.imageUrl, priceCents: p.priceCents, currency: p.currency, merchant: p.merchant, brand: p.brand, url: p.url, postId: post.id, redirectId: p.redirectId)
            }
        }
    }
}
