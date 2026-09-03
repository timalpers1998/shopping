import Foundation

extension JSONDecoder {
    /// Decoder shared by fixtures and Supabase responses: snake_case keys, Postgres-friendly dates.
    static let feed: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        d.dateDecodingStrategy = .custom { decoder in
            let raw = try decoder.singleValueContainer().decode(String.self)
            if let date = PostgresDate.parse(raw) { return date }
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Unparseable date \(raw)"))
        }
        return d
    }()
}

extension JSONEncoder {
    static let feed: JSONEncoder = {
        let e = JSONEncoder()
        e.keyEncodingStrategy = .convertToSnakeCase
        e.dateEncodingStrategy = .iso8601
        return e
    }()
}

enum PostgresDate {
    nonisolated(unsafe) private static let withFraction: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    nonisolated(unsafe) private static let plain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    /// Accepts "2026-09-01T12:00:00.123456+00:00", "2026-09-01T12:00:00Z", "2026-09-01 12:00:00.1+00".
    static func parse(_ raw: String) -> Date? {
        var s = raw.replacingOccurrences(of: " ", with: "T")
        if s.hasSuffix("+00") { s += ":00" }
        // Trim fractional seconds to 3 digits; ISO8601DateFormatter only accepts milliseconds.
        if let dot = s.firstIndex(of: ".") {
            let afterDot = s[s.index(after: dot)...]
            let digits = afterDot.prefix { $0.isNumber }
            let rest = afterDot.dropFirst(digits.count)
            let ms = String(digits.prefix(3)).padding(toLength: 3, withPad: "0", startingAt: 0)
            s = String(s[..<dot]) + "." + ms + rest
            return withFraction.date(from: s) ?? plain.date(from: String(s[..<dot]) + rest)
        }
        return plain.date(from: s)
    }
}
