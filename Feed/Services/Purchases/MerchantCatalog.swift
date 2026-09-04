import Foundation

struct MerchantInfo: Codable, Sendable {
    let domain: String
    let brand: String?
    let category: String?
    var marketplace: Bool? = nil
}

/// Sender-domain lookup for brand and category. Data lives in Resources/merchants.json.
final class MerchantCatalog: Sendable {
    static let shared = MerchantCatalog()
    let entries: [MerchantInfo]
    private let byDomain: [String: MerchantInfo]

    init() {
        let url = Bundle.main.url(forResource: "merchants", withExtension: "json")
        let data = url.flatMap { try? Data(contentsOf: $0) } ?? Data()
        entries = (try? JSONDecoder().decode([MerchantInfo].self, from: data)) ?? []
        byDomain = Dictionary(uniqueKeysWithValues: entries.map { ($0.domain, $0) })
    }

    var domains: [String] { entries.map(\.domain) }

    /// Matches "orders@em.everlane.com" → everlane.com entry.
    func lookup(address: String) -> MerchantInfo? {
        let host = address.split(separator: "@").last.map(String.init)?.lowercased() ?? address.lowercased()
        var parts = host.split(separator: ".").map(String.init)
        while parts.count >= 2 {
            if let e = byDomain[parts.joined(separator: ".")] { return e }
            parts.removeFirst()
        }
        return nil
    }

    static func registrableDomain(_ address: String) -> String {
        let host = address.split(separator: "@").last.map(String.init)?.lowercased() ?? address.lowercased()
        let parts = host.split(separator: ".").map(String.init)
        let multi = ["co.uk", "com.au", "co.jp", "com.br"]
        let last2 = parts.suffix(2).joined(separator: ".")
        return multi.contains(last2) ? parts.suffix(3).joined(separator: ".") : last2
    }

    /// Known brand names for title-prefix matching ("Levi's Men's 501…" → Levi's).
    var brandNames: [String] { entries.compactMap(\.brand) }
}
