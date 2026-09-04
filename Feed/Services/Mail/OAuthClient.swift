import Foundation
import AuthenticationServices
import CryptoKit
import UIKit

struct OAuthProviderConfig: Sendable {
    let authorizationURL: URL
    let tokenURL: URL
    let revokeURL: URL?
    let clientId: String
    let redirectURI: String
    let callbackScheme: String
    let scopes: [String]
    let extraAuthParams: [String: String]

    /// Google "iOS" client: no secret, reversed-client-id redirect.
    static func google(clientId: String) -> OAuthProviderConfig {
        let reversed = clientId.split(separator: ".").reversed().joined(separator: ".")
        return OAuthProviderConfig(
            authorizationURL: URL(string: "https://accounts.google.com/o/oauth2/v2/auth")!,
            tokenURL: URL(string: "https://oauth2.googleapis.com/token")!,
            revokeURL: URL(string: "https://oauth2.googleapis.com/revoke")!,
            clientId: clientId,
            redirectURI: "\(reversed):/oauthredirect",
            callbackScheme: reversed,
            scopes: ["https://www.googleapis.com/auth/gmail.readonly", "openid", "email"],
            extraAuthParams: ["prompt": "select_account consent", "include_granted_scopes": "true"])
    }
}

struct OAuthTokenSet: Codable, Sendable {
    var accessToken: String
    var refreshToken: String?
    var expiresAt: Date
    var scope: String?
    var idToken: String?
    var isExpiringSoon: Bool { expiresAt.timeIntervalSinceNow < 60 }
}

enum OAuthError: LocalizedError {
    case cancelled, badCallback, tokenExchange(String)
    var errorDescription: String? {
        switch self {
        case .cancelled: "Sign-in was cancelled"
        case .badCallback: "The sign-in response was invalid"
        case .tokenExchange(let m): "Could not finish sign-in: \(m)"
        }
    }
}

/// Authorization-code + PKCE flow via ASWebAuthenticationSession. No third-party SDKs.
@MainActor
final class OAuthClient: NSObject, ASWebAuthenticationPresentationContextProviding {
    let config: OAuthProviderConfig
    private var session: ASWebAuthenticationSession?

    init(config: OAuthProviderConfig) { self.config = config }

    func authorize() async throws -> OAuthTokenSet {
        let verifier = Self.randomString(64)
        let challenge = Self.base64url(SHA256.hash(data: Data(verifier.utf8)))
        var comps = URLComponents(url: config.authorizationURL, resolvingAgainstBaseURL: false)!
        var items = [
            URLQueryItem(name: "client_id", value: config.clientId),
            URLQueryItem(name: "redirect_uri", value: config.redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: config.scopes.joined(separator: " ")),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: Self.randomString(16)),
        ]
        for (k, v) in config.extraAuthParams { items.append(URLQueryItem(name: k, value: v)) }
        comps.queryItems = items

        let callback: URL = try await withCheckedThrowingContinuation { cont in
            let s = ASWebAuthenticationSession(url: comps.url!, callbackURLScheme: config.callbackScheme) { url, error in
                if let url { cont.resume(returning: url) }
                else if let e = error as? ASWebAuthenticationSessionError, e.code == .canceledLogin { cont.resume(throwing: OAuthError.cancelled) }
                else { cont.resume(throwing: error ?? OAuthError.badCallback) }
            }
            s.presentationContextProvider = self
            s.prefersEphemeralWebBrowserSession = false
            self.session = s
            s.start()
        }
        guard let code = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "code" })?.value else {
            throw OAuthError.badCallback
        }
        return try await exchange(form: ["grant_type": "authorization_code", "code": code, "code_verifier": verifier, "redirect_uri": config.redirectURI])
    }

    func refresh(_ token: OAuthTokenSet) async throws -> OAuthTokenSet {
        guard let rt = token.refreshToken else { throw OAuthError.tokenExchange("no refresh token") }
        var fresh = try await exchange(form: ["grant_type": "refresh_token", "refresh_token": rt])
        fresh.refreshToken = fresh.refreshToken ?? rt
        return fresh
    }

    func revoke(_ token: OAuthTokenSet) async {
        guard let url = config.revokeURL else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.httpBody = "token=\(token.refreshToken ?? token.accessToken)".data(using: .utf8)
        _ = try? await URLSession.shared.data(for: req)
    }

    private func exchange(form: [String: String]) async throws -> OAuthTokenSet {
        var req = URLRequest(url: config.tokenURL)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var body = form
        body["client_id"] = config.clientId
        req.httpBody = body.map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? $0.value)" }.joined(separator: "&").data(using: .utf8)
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else {
            throw OAuthError.tokenExchange(String(data: data, encoding: .utf8) ?? "http error")
        }
        struct R: Decodable { let access_token: String; let refresh_token: String?; let expires_in: Double?; let scope: String?; let id_token: String? }
        let r = try JSONDecoder().decode(R.self, from: data)
        return OAuthTokenSet(accessToken: r.access_token, refreshToken: r.refresh_token, expiresAt: Date().addingTimeInterval(r.expires_in ?? 3600), scope: r.scope, idToken: r.id_token)
    }

    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows).first { $0.isKeyWindow } ?? ASPresentationAnchor()
        }
    }

    static func randomString(_ n: Int) -> String {
        let chars = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        var bytes = [UInt8](repeating: 0, count: n)
        _ = SecRandomCopyBytes(kSecRandomDefault, n, &bytes)
        return String(bytes.map { chars[Int($0) % chars.count] })
    }
    static func base64url<D: Sequence>(_ d: D) -> String where D.Element == UInt8 {
        Data(d).base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
}
