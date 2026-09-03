import Foundation

struct Product: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let title: String
    let imageUrl: URL?
    let priceCents: Int?
    let currency: String
    let merchant: String
    let brand: String?
    let url: URL
    let redirectId: String?
    let position: Int

    enum CodingKeys: String, CodingKey { case id, title, imageUrl, priceCents, currency, merchant, brand, url, redirectId, position }

    init(id: UUID, title: String, imageUrl: URL?, priceCents: Int?, currency: String = "USD", merchant: String, brand: String? = nil, url: URL, redirectId: String? = nil, position: Int = 0) {
        self.id = id; self.title = title; self.imageUrl = imageUrl; self.priceCents = priceCents; self.currency = currency
        self.merchant = merchant; self.brand = brand; self.url = url; self.redirectId = redirectId; self.position = position
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        imageUrl = try c.decodeIfPresent(URL.self, forKey: .imageUrl)
        priceCents = try c.decodeIfPresent(Int.self, forKey: .priceCents)
        currency = try c.decodeIfPresent(String.self, forKey: .currency) ?? "USD"
        merchant = try c.decodeIfPresent(String.self, forKey: .merchant) ?? ""
        brand = try c.decodeIfPresent(String.self, forKey: .brand)
        url = try c.decode(URL.self, forKey: .url)
        redirectId = try c.decodeIfPresent(String.self, forKey: .redirectId)
        position = try c.decodeIfPresent(Int.self, forKey: .position) ?? 0
    }
}
