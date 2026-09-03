import Foundation

enum PriceFormatter {
    static func string(cents: Int?, currency: String) -> String? {
        guard let cents else { return nil }
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = currency.uppercased()
        f.locale = Locale(identifier: "en_US")
        let amount = Double(cents) / 100
        f.maximumFractionDigits = amount == amount.rounded() ? 0 : 2
        return f.string(from: NSNumber(value: amount))
    }
}

enum CountFormatter {
    static func compact(_ n: Int) -> String {
        switch n {
        case ..<1000: return String(n)
        case ..<1_000_000:
            let v = Double(n) / 1000
            return v < 10 ? String(format: "%.1fK", v).replacingOccurrences(of: ".0K", with: "K") : "\(Int(v))K"
        default:
            let v = Double(n) / 1_000_000
            return v < 10 ? String(format: "%.1fM", v).replacingOccurrences(of: ".0M", with: "M") : "\(Int(v))M"
        }
    }
}

enum RelativeDate {
    static func short(_ date: Date, now: Date = Date()) -> String {
        let s = Int(now.timeIntervalSince(date))
        if s < 60 { return "now" }
        if s < 3600 { return "\(s / 60)m" }
        if s < 86400 { return "\(s / 3600)h" }
        if s < 86400 * 7 { return "\(s / 86400)d" }
        if s < 86400 * 30 { return "\(s / (86400 * 7))w" }
        return "\(s / (86400 * 30))mo"
    }
}
