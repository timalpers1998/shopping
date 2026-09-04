import Foundation
import Supabase

struct PurchaseApplyResult: Decodable, Sendable {
    let importId: UUID?
    let items: Int
    let priceBand: String?
    let followedAuthorIds: [UUID]
}

struct PurchaseImportsSummary: Decodable, Sendable {
    struct Import: Decodable, Sendable, Identifiable { let id: UUID; let provider: String; let accountLabel: String?; let items: Int; let createdAt: Date }
    struct BrandRow: Decodable, Sendable, Identifiable { let brand: String; let items: Int; let imageUrl: String?; var id: String { brand } }
    struct Item: Decodable, Sendable, Identifiable {
        let id: UUID; let title: String; let brand: String?; let merchant: String; let priceCents: Int?; let currency: String
        let purchasedAt: Date; let category: String?; let imageUrl: String?; let productUrl: String?
    }
    let imports: [Import]
    let brands: [BrandRow]
    let items: [Item]
    let tasteApplied: Bool
    let priceBand: String?
    let priceBandSource: String?
}

protocol PurchaseRepository: Sendable {
    func apply(provider: MailProviderKind, accountLabel: String, scanned: Int, orders: [ParsedOrder], setPriceBand: Bool, followBrands: Bool) async throws -> PurchaseApplyResult
    func summary() async throws -> PurchaseImportsSummary
    func deleteAll() async throws
    /// Fills a missing image via the product page; nil when unavailable (anonymous users, failures).
    func scrapeImage(url: String) async -> String?
}

struct LivePurchaseRepository: PurchaseRepository {
    let client: SupabaseClient

    private struct ItemPayload: Encodable {
        let fingerprint: String; let merchant: String; let brand: String?; let title: String; let priceCents: Int?; let currency: String
        let quantity: Int; let purchasedAt: Date; let category: String?; let orderKind: String; let extraction: String; let confidence: Double
        let imageUrl: String?; let productUrl: String?
    }
    private struct Payload: Encodable {
        let provider: String; let accountLabel: String; let messagesScanned: Int; let ordersFound: Int; let setPriceBand: Bool; let followBrands: Bool; let items: [ItemPayload]
    }
    private struct Params: Encodable { let p: Payload }

    func apply(provider: MailProviderKind, accountLabel: String, scanned: Int, orders: [ParsedOrder], setPriceBand: Bool, followBrands: Bool) async throws -> PurchaseApplyResult {
        let items = orders.flatMap { o in o.items.filter(\.included).map { i in
            ItemPayload(fingerprint: o.fingerprint, merchant: o.merchant, brand: i.brand, title: i.title, priceCents: i.priceCents, currency: i.currency,
                        quantity: i.quantity, purchasedAt: o.purchasedAt, category: i.category, orderKind: o.orderKind.rawValue, extraction: o.extraction.rawValue,
                        confidence: o.confidence, imageUrl: i.imageUrl, productUrl: i.productUrl) } }
        let p = Payload(provider: provider.rawValue, accountLabel: accountLabel, messagesScanned: scanned, ordersFound: orders.count, setPriceBand: setPriceBand, followBrands: followBrands, items: items)
        return try await client.rpc("apply_purchase_signals", params: Params(p: p)).execute().value
    }

    func summary() async throws -> PurchaseImportsSummary { try await client.rpc("get_purchase_imports").execute().value }
    func deleteAll() async throws { try await client.rpc("delete_purchase_signals").execute() }

    private struct ScrapeBody: Encodable { let url: String }
    func scrapeImage(url: String) async -> String? {
        guard let session = try? await client.auth.session, !session.user.isAnonymous else { return nil }
        let scraped: ScrapedProduct? = try? await client.functions.invoke("scrape-product", options: .init(body: ScrapeBody(url: url)), decode: { data, _ in
            try JSONDecoder.feed.decode(ScrapedProduct.self, from: data)
        })
        return scraped?.imageUrl
    }
}

/// In-memory store for fixtures mode and UI tests.
actor MockPurchaseStore {
    static let shared = MockPurchaseStore()
    var orders: [ParsedOrder] = []
    var imports: [PurchaseImportsSummary.Import] = []
    func add(_ o: [ParsedOrder], label: String) { orders += o; imports.append(.init(id: UUID(), provider: "fixture", accountLabel: label, items: o.reduce(0) { $0 + $1.items.filter(\.included).count }, createdAt: Date())) }
    func clear() { orders = []; imports = [] }
}

struct MockPurchaseRepository: PurchaseRepository {
    func apply(provider: MailProviderKind, accountLabel: String, scanned: Int, orders: [ParsedOrder], setPriceBand: Bool, followBrands: Bool) async throws -> PurchaseApplyResult {
        try? await Task.sleep(for: .milliseconds(500))
        await MockPurchaseStore.shared.add(orders, label: accountLabel)
        let n = orders.reduce(0) { $0 + $1.items.filter(\.included).count }
        return PurchaseApplyResult(importId: UUID(), items: n, priceBand: "mid", followedAuthorIds: [])
    }
    func summary() async throws -> PurchaseImportsSummary {
        let orders = await MockPurchaseStore.shared.orders
        let imports = await MockPurchaseStore.shared.imports
        let items = orders.flatMap { o in o.items.filter(\.included).map { i in
            PurchaseImportsSummary.Item(id: i.id, title: i.title, brand: i.brand, merchant: o.merchant, priceCents: i.priceCents, currency: i.currency,
                                        purchasedAt: o.purchasedAt, category: i.category, imageUrl: i.imageUrl, productUrl: i.productUrl) } }
        let grouped = Dictionary(grouping: items, by: { $0.brand ?? $0.merchant })
        let brands = grouped.map { PurchaseImportsSummary.BrandRow(brand: $0.key, items: $0.value.count, imageUrl: $0.value.first?.imageUrl) }.sorted { $0.items > $1.items }
        return PurchaseImportsSummary(imports: imports, brands: brands, items: items, tasteApplied: !orders.isEmpty, priceBand: orders.isEmpty ? nil : "mid", priceBandSource: orders.isEmpty ? nil : "purchases")
    }
    func deleteAll() async throws { await MockPurchaseStore.shared.clear() }
    func scrapeImage(url: String) async -> String? {
        let host = URL(string: url)?.host()?.replacingOccurrences(of: "www.", with: "") ?? "x"
        return "https://loremflickr.com/600/800/clothes?lock=\(1 + host.count % 9)"
    }
}
