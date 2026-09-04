import Foundation

/// Values injected from Secrets.xcconfig via Info.plist. Missing values mean "run against fixtures".
enum AppConfig {
    static var supabaseURL: URL? { url(for: "SUPABASE_URL") }
    static var supabaseAnonKey: String? { string(for: "SUPABASE_ANON_KEY") }
    static var redirectBaseURL: URL? { url(for: "REDIRECT_BASE_URL") }
    static var hasBackend: Bool { supabaseURL != nil && supabaseAnonKey != nil }
    static var googleOAuthClientId: String? { string(for: "GOOGLE_OAUTH_CLIENT_ID") }

    private static func string(for key: String) -> String? {
        guard let v = Bundle.main.object(forInfoDictionaryKey: key) as? String, !v.isEmpty, !v.hasPrefix("YOUR-"), !v.contains("YOUR-") else { return nil }
        return v
    }
    private static func url(for key: String) -> URL? { string(for: key).flatMap(URL.init(string:)) }
}
