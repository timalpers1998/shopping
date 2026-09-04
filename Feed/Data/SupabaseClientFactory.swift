import Foundation
import Supabase

enum SupabaseClientFactory {
    static func make(url: URL, anonKey: String) -> SupabaseClient {
        SupabaseClient(
            supabaseURL: url,
            supabaseKey: anonKey,
            options: SupabaseClientOptions(
                db: .init(encoder: .feed, decoder: .feed),
                auth: .init(redirectToURL: URL(string: "feed://auth/callback"), flowType: .pkce),
                global: .init(headers: ["x-client-info": "feed-ios/0.1"])
            )
        )
    }
}
