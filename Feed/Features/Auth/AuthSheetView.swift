import SwiftUI
import AuthenticationServices
import CryptoKit

/// Sign in with Apple or a 6-digit email code. Presented whenever an anonymous user tries to post, comment, or manage their account.
struct AuthSheetView: View {
    let reason: String
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    @State private var email = ""
    @State private var code = ""
    @State private var codeSent = false
    @State private var busy = false
    @State private var error: String?
    @State private var nonce = ""

    var body: some View {
        VStack(spacing: 20) {
            Capsule().fill(.white.opacity(0.3)).frame(width: 36, height: 4).padding(.top, 8)
            VStack(spacing: 6) {
                Text("Sign in to \(reason)").font(.title2.bold())
                Text("Your likes, saves and taste carry over.").font(.subheadline).foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.center)

            SignInWithAppleButton(.signIn) { request in
                nonce = Self.randomNonce()
                request.requestedScopes = [.fullName, .email]
                request.nonce = Self.sha256(nonce)
            } onCompletion: { result in
                Task { await handleApple(result) }
            }
            .signInWithAppleButtonStyle(.white)
            .frame(height: 50)
            .clipShape(RoundedRectangle(cornerRadius: 12))

            HStack { Rectangle().fill(.white.opacity(0.2)).frame(height: 1); Text("or").font(.caption).foregroundStyle(.secondary); Rectangle().fill(.white.opacity(0.2)).frame(height: 1) }

            if !codeSent {
                TextField("Email", text: $email)
                    .textContentType(.emailAddress).keyboardType(.emailAddress).textInputAutocapitalization(.never).autocorrectionDisabled()
                    .padding(14).background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))
                    .accessibilityIdentifier("auth-email")
                Button { Task { await sendCode() } } label: { label("Send code") }
                    .disabled(busy || !email.contains("@"))
                    .accessibilityIdentifier("auth-send-code")
            } else {
                Text("We sent a 6-digit code to \(email)").font(.footnote).foregroundStyle(.secondary)
                TextField("123456", text: $code)
                    .textContentType(.oneTimeCode).keyboardType(.numberPad).font(.title2.monospacedDigit()).multilineTextAlignment(.center)
                    .padding(14).background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))
                    .accessibilityIdentifier("auth-code")
                Button { Task { await verify() } } label: { label("Verify") }
                    .disabled(busy || code.count < 6)
                    .accessibilityIdentifier("auth-verify")
                Button("Use a different email") { codeSent = false; code = "" }.font(.footnote).foregroundStyle(.secondary)
            }

            if let error { Text(error).font(.footnote).foregroundStyle(.red).multilineTextAlignment(.center) }
            Button("Not now") { dismiss() }.font(.footnote).foregroundStyle(.secondary).padding(.top, 4)
                .accessibilityIdentifier("auth-close")
            Spacer(minLength: 0)
        }
        .padding(20)
        .background(Theme.background)
        .foregroundStyle(.white)
    }

    private func label(_ text: String) -> some View {
        Group { if busy { ProgressView().tint(.black) } else { Text(text).bold() } }
            .frame(maxWidth: .infinity).frame(height: 50)
            .background(.white, in: RoundedRectangle(cornerRadius: 12)).foregroundStyle(.black)
    }

    private func sendCode() async {
        guard let auth = env.auth else { dismiss(); return }
        busy = true; error = nil
        do { try await auth.sendEmailCode(to: email); codeSent = true } catch { self.error = error.localizedDescription }
        busy = false
    }

    private func verify() async {
        guard let auth = env.auth else { dismiss(); return }
        busy = true; error = nil
        do {
            try await auth.verifyEmailCode(code)
            await env.refreshMe()
            dismiss()
        } catch { self.error = error.localizedDescription }
        busy = false
    }

    private func handleApple(_ result: Result<ASAuthorization, Error>) async {
        guard let auth = env.auth else { dismiss(); return }
        switch result {
        case .failure(let e):
            if (e as? ASAuthorizationError)?.code != .canceled { error = e.localizedDescription }
        case .success(let authorization):
            guard let cred = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = cred.identityToken, let token = String(data: tokenData, encoding: .utf8) else { error = "Apple did not return a token"; return }
            busy = true
            let name = [cred.fullName?.givenName, cred.fullName?.familyName].compactMap { $0 }.joined(separator: " ")
            do {
                try await auth.signInWithApple(idToken: token, nonce: nonce, fullName: name.isEmpty ? nil : name)
                await env.refreshMe()
                dismiss()
            } catch { self.error = error.localizedDescription }
            busy = false
        }
    }

    static func randomNonce(length: Int = 32) -> String {
        let chars = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var bytes = [UInt8](repeating: 0, count: length)
        _ = SecRandomCopyBytes(kSecRandomDefault, length, &bytes)
        return String(bytes.map { chars[Int($0) % chars.count] })
    }
    static func sha256(_ s: String) -> String {
        SHA256.hash(data: Data(s.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
