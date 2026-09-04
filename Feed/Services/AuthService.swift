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
    }

    private(set) var state: State = .loading
    let client: SupabaseClient
    private var observer: Task<Void, Never>?

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

    func signOut() async {
        try? await client.auth.signOut()
        await ensureSession()
    }
}
