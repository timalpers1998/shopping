import Foundation
import Observation
import Supabase

/// Owns the Supabase session. Every launch has a session: anonymous until the user signs in.
@MainActor
@Observable
final class AuthService {
    enum State: Equatable {
        case loading
        case anonymous(userId: UUID)
        case signedIn(userId: UUID)
        var userId: UUID? {
            switch self {
            case .loading: nil
            case .anonymous(let id), .signedIn(let id): id
            }
        }
        var isAnonymous: Bool { if case .anonymous = self { return true } else { return false } }
        var isSignedIn: Bool { if case .signedIn = self { return true } else { return false } }
    }

    enum AuthError: LocalizedError {
        case noSession, mergeFailed(String)
        var errorDescription: String? {
            switch self {
            case .noSession: "No session"
            case .mergeFailed(let m): "Could not carry over your activity: \(m)"
            }
        }
    }

    private(set) var state: State = .loading
    let client: SupabaseClient
    private var observer: Task<Void, Never>?
    /// Set while an email OTP is in flight so the verify step knows which flow to use.
    private var pendingEmailFlow: EmailFlow?
    private enum EmailFlow { case convertAnonymous(email: String), signIn(email: String, anonToken: String?) }

    init(client: SupabaseClient) {
        self.client = client
    }

    /// Restores a persisted session or creates an anonymous one. Safe to call repeatedly.
    func ensureSession() async {
        if let session = try? await client.auth.session {
            apply(session)
        } else {
            do {
                let session = try await client.auth.signInAnonymously()
                apply(session)
            } catch {
                print("[Auth] anonymous sign-in failed: \(error)")
            }
        }
        if observer == nil {
            observer = Task { [weak self] in
                guard let self else { return }
                for await (event, session) in client.auth.authStateChanges {
                    guard !Task.isCancelled else { break }
                    switch event {
                    case .signedIn, .tokenRefreshed, .userUpdated, .initialSession:
                        if let session { self.apply(session) }
                    case .signedOut:
                        self.state = .loading
                        await self.ensureSession()
                    default: break
                    }
                }
            }
        }
    }

    private func apply(_ session: Session) {
        let id = session.user.id
        state = session.user.isAnonymous ? .anonymous(userId: id) : .signedIn(userId: id)
    }

    var accessToken: String? {
        get async { try? await client.auth.session.accessToken }
    }

    // MARK: Sign in with Apple

    func signInWithApple(idToken: String, nonce: String, fullName: String?) async throws {
        let anonToken = state.isAnonymous ? await accessToken : nil
        let session = try await client.auth.signInWithIdToken(credentials: .init(provider: .apple, idToken: idToken, nonce: nonce))
        apply(session)
        if let fullName, !fullName.isEmpty {
            try? await client.from("profiles").update(["display_name": fullName]).eq("id", value: session.user.id).execute()
        }
        if let anonToken { await mergeAnonymous(token: anonToken) }
    }

    // MARK: Email OTP

    /// Sends a 6-digit code. Anonymous users are converted in place; existing accounts sign in and merge.
    func sendEmailCode(to email: String) async throws {
        let email = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if state.isAnonymous {
            do {
                try await client.auth.update(user: UserAttributes(email: email))
                pendingEmailFlow = .convertAnonymous(email: email)
                return
            } catch {
                // Email already belongs to another account: fall back to a normal sign-in + merge.
                let anonToken = await accessToken
                try await client.auth.signInWithOTP(email: email, shouldCreateUser: false)
                pendingEmailFlow = .signIn(email: email, anonToken: anonToken)
                return
            }
        }
        try await client.auth.signInWithOTP(email: email, shouldCreateUser: true)
        pendingEmailFlow = .signIn(email: email, anonToken: nil)
    }

    func verifyEmailCode(_ code: String) async throws {
        guard let flow = pendingEmailFlow else { throw AuthError.noSession }
        switch flow {
        case .convertAnonymous(let email):
            let response = try await client.auth.verifyOTP(email: email, token: code, type: .emailChange)
            if let session = response.session { apply(session) }
        case .signIn(let email, let anonToken):
            let response = try await client.auth.verifyOTP(email: email, token: code, type: .email)
            if let session = response.session { apply(session) }
            if let anonToken { await mergeAnonymous(token: anonToken) }
        }
        pendingEmailFlow = nil
    }

    /// Magic-link / PKCE callback (feed://auth/callback?code=...).
    func handle(url: URL) async {
        guard url.host == "auth" else { return }
        if let session = try? await client.auth.session(from: url) { apply(session) }
    }

    private struct MergeBody: Encodable { let anonAccessToken: String }
    private func mergeAnonymous(token: String) async {
        do {
            let _: [String: AnyJSON] = try await client.functions.invoke("merge-anonymous", options: .init(body: MergeBody(anonAccessToken: token)))
        } catch {
            print("[Auth] merge-anonymous failed: \(error)")
        }
    }

    func signOut() async {
        try? await client.auth.signOut()
        await ensureSession()
    }
}
