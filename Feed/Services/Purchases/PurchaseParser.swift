import Foundation

enum OrderKind: String, Sendable, Codable { case confirmation, shipped, receipt, other }
enum OrderClass: Sendable, Equatable { case order(OrderKind), notAnOrder }
enum ExtractionMethod: String, Sendable, Codable { case jsonld, heuristic, scrape }

struct PurchaseItem: Sendable, Identifiable, Hashable, Codable {
    var id = UUID()
    var title: String
    var brand: String?
    var priceCents: Int?
    var currency = "USD"
    var quantity = 1
    var category: String?
    var imageUrl: String?
    var productUrl: String?
    var included = true
}

struct ParsedOrder: Sendable, Identifiable, Codable {
    let id: String
    let fingerprint: String
    let merchant: String
    let merchantBrand: String?
    let orderKind: OrderKind
    let purchasedAt: Date
    var orderTotalCents: Int?
    var currency = "USD"
    var items: [PurchaseItem]
    let extraction: ExtractionMethod
    var confidence: Double
}

/// Subject/sender classification shared by providers (pre-filter) and the parser.
enum OrderClassifier {
    static let negative = try! NSRegularExpression(pattern: #"(?i)\b(unsubscribe|newsletter|% off|percent off|sale ends|flash sale|last chance|password|verify your|return (has been|is) (processed|complete)|refund (issued|processed)|cancell?ed|survey|review your purchase|rate your)\b"#)
    static let confirmation = try! NSRegularExpression(pattern: #"(?i)(order (confirmation|confirmed|#|number|received)|your order|thanks for (your|shopping)|thank you for your (order|purchase)|we('ve| have) received your order|ordered:)"#)
    static let shipped = try! NSRegularExpression(pattern: #"(?i)(has shipped|shipped!|your shipment|on its way|is on the way|out for delivery|has been delivered|delivered:)"#)
    static let receipt = try! NSRegularExpression(pattern: #"(?i)(receipt|invoice|payment (received|confirmation))"#)

    static func classify(subject: String, from: String) -> OrderClass {
        let s = subject
        if negative.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) != nil { return .notAnOrder }
        if confirmation.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) != nil { return .order(.confirmation) }
        if shipped.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) != nil { return .order(.shipped) }
        if receipt.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) != nil { return .order(.receipt) }
        // Known merchant senders get the benefit of the doubt when the subject is neutral.
        if MerchantCatalog.shared.lookup(address: from) != nil, s.range(of: #"(?i)\b(order|purchase|shipment)\b"#, options: .regularExpression) != nil { return .order(.other) }
        return .notAnOrder
    }
}

/// Turns one order email into structured items. Runs entirely on-device.
enum PurchaseParser {
    static func parse(_ m: MailMessage) -> ParsedOrder? {
        guard case .order(let kind) = OrderClassifier.classify(subject: m.subject, from: m.fromAddress) else { return nil }
        let info = MerchantCatalog.shared.lookup(address: m.fromAddress)
        let merchant = info?.domain ?? MerchantCatalog.registrableDomain(m.fromAddress)
        let merchantBrand = (info?.marketplace ?? false) ? nil : info?.brand
        let category = info?.category
        let fingerprint = Self.sha256("\(m.provider.rawValue):\(m.id)")

        if let html = m.html, let order = JSONLDOrderExtractor.extract(html: html) {
            var items = order.items
            for i in items.indices {
                items[i].brand = items[i].brand ?? merchantBrand ?? Self.brandFromTitle(items[i].title)
                items[i].category = items[i].category ?? category ?? Self.categoryFromTitle(items[i].title)
            }
            let priced = items.compactMap(\.priceCents)
            if !items.isEmpty {
                return ParsedOrder(id: m.id, fingerprint: fingerprint, merchant: merchant, merchantBrand: merchantBrand,
                                   orderKind: kind, purchasedAt: order.orderDate ?? m.receivedAt, orderTotalCents: order.total ?? (priced.isEmpty ? nil : priced.reduce(0, +)),
                                   currency: order.currency ?? "USD", items: items, extraction: .jsonld, confidence: 0.95)
            }
        }

        let h = HeuristicOrderExtractor.extract(message: m, merchantBrand: merchantBrand, category: category)
        guard !h.items.isEmpty else { return nil }
        var items = h.items
        for i in items.indices {
            items[i].brand = items[i].brand ?? merchantBrand ?? Self.brandFromTitle(items[i].title)
            items[i].category = items[i].category ?? category ?? Self.categoryFromTitle(items[i].title)
        }
        return ParsedOrder(id: m.id, fingerprint: fingerprint, merchant: merchant, merchantBrand: merchantBrand, orderKind: kind,
                           purchasedAt: m.receivedAt, orderTotalCents: h.total, currency: h.currency, items: items, extraction: .heuristic, confidence: h.confidence)
    }

    /// Collapses confirmation + shipped emails for the same order into one row per item.
    static func dedupe(_ orders: [ParsedOrder]) -> [ParsedOrder] {
        var out: [ParsedOrder] = []
        for o in orders.sorted(by: { $0.purchasedAt > $1.purchasedAt }) {
            if let j = out.firstIndex(where: { $0.merchant == o.merchant && abs($0.purchasedAt.timeIntervalSince(o.purchasedAt)) < 14 * 86400 &&
                Set($0.items.map { normalize($0.title) }).intersection(o.items.map { normalize($0.title) }).count > 0 }) {
                // keep the one with prices / more items
                if (o.items.compactMap(\.priceCents).count, o.items.count) > (out[j].items.compactMap(\.priceCents).count, out[j].items.count) { out[j] = o }
            } else {
                out.append(o)
            }
        }
        return out
    }

    static func normalize(_ s: String) -> String {
        s.lowercased().replacingOccurrences(of: #"[^a-z0-9 ]"#, with: "", options: .regularExpression).split(separator: " ").prefix(6).joined(separator: " ")
    }

    static func brandFromTitle(_ title: String) -> String? {
        let lower = title.lowercased()
        return MerchantCatalog.shared.brandNames.first { lower.hasPrefix($0.lowercased()) || lower.contains(" " + $0.lowercased() + " ") }
    }

    static func categoryFromTitle(_ title: String) -> String? {
        let t = title.lowercased()
        if t.range(of: #"\b(dress|jean|denim|coat|jacket|sneaker|shoe|boot|loafer|tee|t-shirt|shirt|blouse|sweater|cardigan|hoodie|pant|trouser|skirt|legging|bra|sock|hat|cap|bag|tote|belt|scarf|blazer|suit|short|jumper|parka|puffer|fleece|sandal|heel|flat|romper|jumpsuit|top|tank|polo|chino|cashmere|linen|wool)s?\b"#, options: .regularExpression) != nil { return "fashion" }
        if t.range(of: #"\b(serum|lipstick|mascara|foundation|moisturizer|cleanser|shampoo|conditioner|perfume|fragrance|sunscreen|blush|eyeliner|palette|skincare|toner)s?\b"#, options: .regularExpression) != nil { return "beauty" }
        if t.range(of: #"\b(sofa|lamp|duvet|sheet|pillow|rug|candle|vase|mug|table|chair|planter|blanket|towel|frame|shelf)s?\b"#, options: .regularExpression) != nil { return "home" }
        return nil
    }

    static func sha256(_ s: String) -> String {
        import_CryptoKit_sha256(s)
    }
}

import CryptoKit
private func import_CryptoKit_sha256(_ s: String) -> String {
    SHA256.hash(data: Data(s.utf8)).map { String(format: "%02x", $0) }.joined()
}

/// Tier 1: Schema.org JSON-LD `Order` / `ParcelDelivery` blocks embedded in receipt HTML.
enum JSONLDOrderExtractor {
    struct Result { var items: [PurchaseItem]; var merchant: String?; var orderDate: Date?; var total: Int?; var currency: String? }

    static func extract(html: String) -> Result? {
        let re = try! NSRegularExpression(pattern: #"<script[^>]+type=["']application/ld\+json["'][^>]*>([\s\S]*?)</script>"#, options: .caseInsensitive)
        var result = Result(items: [], merchant: nil, orderDate: nil, total: nil, currency: nil)
        for m in re.matches(in: html, range: NSRange(html.startIndex..., in: html)) {
            guard let r = Range(m.range(at: 1), in: html), let data = html[r].trimmingCharacters(in: .whitespacesAndNewlines).data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) else { continue }
            walk(json, into: &result)
        }
        return result.items.isEmpty ? nil : result
    }

    private static func walk(_ node: Any, into r: inout Result) {
        if let arr = node as? [Any] { for n in arr { walk(n, into: &r) }; return }
        guard let obj = node as? [String: Any] else { return }
        let types: [String] = (obj["@type"] as? [String]) ?? (obj["@type"] as? String).map { [$0] } ?? []
        if types.contains("Order") {
            r.merchant = name(obj["merchant"]) ?? name(obj["seller"]) ?? r.merchant
            if let d = obj["orderDate"] as? String { r.orderDate = PostgresDate.parse(d) ?? ISO8601DateFormatter().date(from: d) }
            if let total = obj["price"] ?? (obj["totalPrice"]) { r.total = cents(total); r.currency = obj["priceCurrency"] as? String ?? r.currency }
            let offers: [Any] = (obj["acceptedOffer"] as? [Any]) ?? (obj["acceptedOffer"]).map { [$0] } ?? []
            for o in offers { if let item = item(fromOffer: o) { r.items.append(item) } }
        } else if types.contains("ParcelDelivery") {
            if let part = obj["partOfOrder"] as? [String: Any] { r.merchant = name(part["merchant"]) ?? r.merchant }
            let shipped: [Any] = (obj["itemShipped"] as? [Any]) ?? (obj["itemShipped"]).map { [$0] } ?? []
            for p in shipped { if let item = item(fromProduct: p, price: nil, currency: nil, qty: 1) { r.items.append(item) } }
        } else if let graph = obj["@graph"] {
            walk(graph, into: &r)
        }
    }

    private static func item(fromOffer o: Any) -> PurchaseItem? {
        guard let offer = o as? [String: Any] else { return nil }
        let qty = ((offer["eligibleQuantity"] as? [String: Any])?["value"]).flatMap { Int("\($0)") } ?? 1
        return item(fromProduct: offer["itemOffered"], price: offer["price"], currency: offer["priceCurrency"] as? String, qty: qty)
    }

    private static func item(fromProduct p: Any?, price: Any?, currency: String?, qty: Int) -> PurchaseItem? {
        guard let prod = p as? [String: Any], let title = prod["name"] as? String, !title.isEmpty else { return nil }
        let image: String? = (prod["image"] as? String) ?? ((prod["image"] as? [Any])?.first as? String) ?? ((prod["image"] as? [String: Any])?["url"] as? String)
        var item = PurchaseItem(title: title)
        item.brand = name(prod["brand"])
        item.priceCents = cents(price)
        item.currency = currency ?? "USD"
        item.quantity = max(qty, 1)
        item.imageUrl = image
        item.productUrl = prod["url"] as? String
        return item
    }

    private static func name(_ v: Any?) -> String? {
        if let s = v as? String { return s }
        if let d = v as? [String: Any] { return d["name"] as? String }
        return nil
    }

    static func cents(_ v: Any?) -> Int? {
        if let n = v as? NSNumber { return Int((n.doubleValue * 100).rounded()) }
        if let s = v as? String { let cleaned = s.replacingOccurrences(of: #"[^0-9.]"#, with: "", options: .regularExpression); return Double(cleaned).map { Int(($0 * 100).rounded()) } }
        return nil
    }
}

/// Tier 2: sender + subject + price-line heuristics over the text version of the email.
enum HeuristicOrderExtractor {
    struct Result { var items: [PurchaseItem]; var total: Int?; var currency: String; var confidence: Double }

    private static let price = try! NSRegularExpression(pattern: #"(?:(\$|€|£|USD|EUR|GBP|CAD)\s?)(\d{1,5}(?:,\d{3})*(?:\.\d{2})?)"#)
    private static let stop = try! NSRegularExpression(pattern: #"(?i)^(sub ?total|shipping|tax|total|order total|grand total|discount|gift card|estimated|delivery|savings|reward|points|balance|due|you saved|promo|coupon|payment|paid with|visa|mastercard|amex|card ending)"#)
    private static let qty = try! NSRegularExpression(pattern: #"(?i)\b(?:qty|quantity)[:\s]*(\d+)\b|\bx\s?(\d+)\b"#)
    private static let variant = try! NSRegularExpression(pattern: #"(?i)^(qty|quantity|colou?r|size|style|sku|item ?#|order ?#|order number|hi |hello|thanks|thank you|we('ve| have) received)|[·|]| / |: |^\d"#)

    /// A line that could be a product name: not a money line, not a stop word, not a variant/quantity line.
    static func titleLike(_ line: String) -> Bool {
        guard line.count >= 3, line.count <= 120 else { return false }
        let ns = line as NSString
        if stop.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)) != nil { return false }
        if variant.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)) != nil { return false }
        if price.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)) != nil { return false }
        return line.rangeOfCharacter(from: .letters) != nil
    }

    static func extract(message m: MailMessage, merchantBrand: String?, category: String?) -> Result {
        var items: [PurchaseItem] = []
        var total: Int? = nil
        var currency = "USD"

        // Amazon-style subjects carry the item title.
        if let r = m.subject.range(of: #"(?:order of|Ordered:|Shipped:|Delivered:)\s*"([^"]+)""#, options: .regularExpression) {
            let inner = String(m.subject[r])
            if let q = inner.range(of: #""([^"]+)""#, options: .regularExpression) {
                let title = String(inner[q]).trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                items.append(PurchaseItem(title: title))
            }
        }

        let text = m.text ?? m.html.map(Self.htmlToText) ?? ""
        let lines = text.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        var buffer: [String] = []   // candidate lines since the last price line
        for (idx, line) in lines.enumerated() {
            let ns = line as NSString
            if let pm = price.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)) {
                let sym = ns.substring(with: pm.range(at: 1))
                currency = ["€": "EUR", "£": "GBP", "EUR": "EUR", "GBP": "GBP", "CAD": "CAD"][sym] ?? "USD"
                let amount = Int((Double(ns.substring(with: pm.range(at: 2)).replacingOccurrences(of: ",", with: "")) ?? 0) * 100)
                let before = ns.substring(to: pm.range.location).trimmingCharacters(in: CharacterSet(charactersIn: " :-–—\t"))
                let label = before.count >= 3 ? before : buffer.last(where: titleLike)
                if let label, stop.firstMatch(in: label, range: NSRange(location: 0, length: (label as NSString).length)) != nil {
                    if label.range(of: #"(?i)(order )?total"#, options: .regularExpression) != nil { total = amount }
                } else if let label, label.count >= 3, label.count <= 120, amount > 0, !items.contains(where: { $0.title == label }) {
                    var item = PurchaseItem(title: label)
                    item.priceCents = amount
                    item.currency = currency
                    let window = lines[max(0, idx - 1)...min(lines.count - 1, idx + 2)].joined(separator: " ")
                    if let qm = qty.firstMatch(in: window, range: NSRange(window.startIndex..., in: window)) {
                        for g in 1...2 { if let rr = Range(qm.range(at: g), in: window), let n = Int(window[rr]) { item.quantity = max(1, n) } }
                    }
                    items.append(item)
                }
                buffer.removeAll()
            } else {
                buffer.append(line)
                if buffer.count > 6 { buffer.removeFirst() }
            }
        }

        // Product images: assign in order, skipping tracking pixels and logos.
        if let html = m.html {
            let imgs = Self.productImages(html)
            for i in items.indices where items[i].imageUrl == nil && i < imgs.count { items[i].imageUrl = imgs[i] }
            let links = Self.productLinks(html)
            for i in items.indices where items[i].productUrl == nil && i < links.count { items[i].productUrl = links[i] }
        }
        for i in items.indices { items[i].brand = items[i].brand ?? merchantBrand; items[i].category = items[i].category ?? category }
        let conf = items.isEmpty ? 0 : min(0.85, 0.5 + 0.1 * Double(items.filter { $0.priceCents != nil }.count) + (total != nil ? 0.1 : 0))
        return Result(items: items, total: total, currency: currency, confidence: conf)
    }

    static func htmlToText(_ html: String) -> String {
        var s = html
        s = s.replacingOccurrences(of: #"(?is)<(style|script|head)[^>]*>.*?</\1>"#, with: " ", options: .regularExpression)
        s = s.replacingOccurrences(of: #"(?i)<br\s*/?>|</(p|div|tr|li|h\d|td|th)>"#, with: "\n", options: .regularExpression)
        s = s.replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
        let entities = ["&amp;": "&", "&nbsp;": " ", "&quot;": "\"", "&#39;": "'", "&apos;": "'", "&lt;": "<", "&gt;": ">", "&#8217;": "'", "&rsquo;": "'"]
        for (k, v) in entities { s = s.replacingOccurrences(of: k, with: v) }
        s = s.replacingOccurrences(of: #"[ \t]+"#, with: " ", options: .regularExpression)
        return s.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.joined(separator: "\n")
    }

    static func productImages(_ html: String) -> [String] {
        let re = try! NSRegularExpression(pattern: #"<img[^>]+src=["']([^"']+)["'][^>]*>"#, options: .caseInsensitive)
        return re.matches(in: html, range: NSRange(html.startIndex..., in: html)).compactMap { m -> String? in
            guard let r = Range(m.range(at: 1), in: html), let tag = Range(m.range, in: html) else { return nil }
            let src = String(html[r]); let t = html[tag].lowercased()
            if src.hasSuffix(".gif") || t.contains("width=\"1\"") || t.contains("height=\"1\"") || t.contains("pixel") || t.contains("track") || t.contains("logo") || t.contains("icon") || t.contains("badge") || t.contains("social") { return nil }
            return src.hasPrefix("//") ? "https:" + src : src
        }
    }

    static func productLinks(_ html: String) -> [String] {
        let re = try! NSRegularExpression(pattern: #"<a[^>]+href=["'](https?://[^"']+)["'][^>]*>"#, options: .caseInsensitive)
        var out: [String] = []
        for m in re.matches(in: html, range: NSRange(html.startIndex..., in: html)) {
            guard let r = Range(m.range(at: 1), in: html) else { continue }
            let href = String(html[r])
            if href.range(of: #"/(products?|dp|p|item|shop)/"#, options: .regularExpression) != nil, !out.contains(href) { out.append(href) }
        }
        return out
    }
}
