import Foundation
import Supabase

struct QuizCatalog: Codable, Sendable {
    struct Style: Codable, Sendable, Identifiable, Hashable { let slug: String; let label: String; let imageUrl: URL?; var id: String { slug } }
    struct Brand: Codable, Sendable, Identifiable, Hashable { let id: UUID; let name: String; let priceBand: String; let logoUrl: URL? }
    let styles: [Style]
    let brands: [Brand]
}

struct QuizAnswers: Sendable {
    var audience = "both"
    var priceBand = "mid"
    var styles: Set<String> = []
    var brandIds: Set<UUID> = []
}

protocol TasteRepository: Sendable {
    func catalog() async throws -> QuizCatalog
    func submit(_ answers: QuizAnswers) async throws
}

struct LiveTasteRepository: TasteRepository {
    let client: SupabaseClient
    private struct Params: Encodable { let pAudience: String; let pPriceBand: String; let pStyles: [String]; let pBrandIds: [UUID] }
    func catalog() async throws -> QuizCatalog { try await client.rpc("get_quiz_catalog").execute().value }
    func submit(_ a: QuizAnswers) async throws {
        try await client.rpc("submit_quiz", params: Params(pAudience: a.audience, pPriceBand: a.priceBand, pStyles: Array(a.styles), pBrandIds: Array(a.brandIds))).execute()
    }
}

struct MockTasteRepository: TasteRepository {
    func catalog() async throws -> QuizCatalog {
        let slugs = ["minimalist", "old_money", "streetwear", "athleisure", "workwear", "scandi", "model_off_duty", "gorpcore", "coastal", "cottagecore", "y2k", "preppy", "glam", "vintage", "boho", "grunge", "coquette", "western"]
        let brands = ["H&M", "Zara", "Uniqlo", "Aritzia", "Madewell", "J.Crew", "Everlane", "Free People", "Lululemon", "Nike", "Levi's", "Reformation", "Ganni", "COS", "Arc'teryx", "Ralph Lauren", "Toteme", "The Row", "Miu Miu", "Prada"]
        return QuizCatalog(
            styles: slugs.map { .init(slug: $0, label: $0.replacingOccurrences(of: "_", with: " ").capitalized, imageUrl: URL(string: "https://picsum.photos/seed/style-\($0)/600/800")) },
            brands: brands.enumerated().map { i, n in .init(id: UUID(uuidString: String(format: "b0000000-0000-4000-a000-%012d", i))!, name: n, priceBand: ["budget", "mid", "premium", "luxury"][i / 5], logoUrl: nil) })
    }
    func submit(_ answers: QuizAnswers) async throws { try? await Task.sleep(for: .milliseconds(300)) }
}
