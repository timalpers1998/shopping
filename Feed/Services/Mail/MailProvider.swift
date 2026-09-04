import Foundation

enum MailProviderKind: String, Codable, Sendable { case gmail, outlook, fixture }

/// Provider-neutral shape of one email. Bodies stay in memory on the device and are never uploaded.
struct MailMessage: Sendable, Identifiable, Codable {
    let id: String
    let provider: MailProviderKind
    let fromAddress: String
    let fromName: String?
    let subject: String
    let receivedAt: Date
    let html: String?
    let text: String?
}

struct MailAccount: Sendable {
    let kind: MailProviderKind
    /// Masked, e.g. "t•••@gmail.com". This is the only account detail that may reach the backend.
    let label: String
}

struct ScanProgress: Sendable, Equatable {
    var scanned = 0
    var total = 0
}

protocol MailProvider: Sendable {
    var kind: MailProviderKind { get }
    var isAvailable: Bool { get }
    func connect() async throws -> MailAccount
    /// Streams candidate messages (already narrowed to likely order emails).
    func scan(progress: @escaping @Sendable (ScanProgress) -> Void) -> AsyncThrowingStream<MailMessage, Error>
    func disconnect() async
}

extension String {
    /// "tim.alpers@icloud.com" → "t•••@icloud.com"
    var maskedEmail: String {
        guard let at = firstIndex(of: "@") else { return "•••" }
        let local = self[..<at]
        return String(local.prefix(1)) + "•••" + String(self[at...])
    }
}
