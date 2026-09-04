import Foundation

/// Serves the bundled sample emails (Resources/Fixtures/emails/email_*.json). Used in fixtures mode and UI tests.
struct FixtureMailProvider: MailProvider {
    let kind: MailProviderKind = .fixture
    var isAvailable: Bool { true }

    func connect() async throws -> MailAccount {
        try? await Task.sleep(for: .milliseconds(400))
        return MailAccount(kind: .fixture, label: "t•••@example.com")
    }

    func scan(progress: @escaping @Sendable (ScanProgress) -> Void) -> AsyncThrowingStream<MailMessage, Error> {
        AsyncThrowingStream { continuation in
            Task {
                let messages = Self.loadAll()
                var p = ScanProgress(scanned: 0, total: messages.count)
                progress(p)
                for m in messages {
                    try? await Task.sleep(for: .milliseconds(150))
                    p.scanned += 1
                    progress(p)
                    continuation.yield(m)
                }
                continuation.finish()
            }
        }
    }

    func disconnect() async {}

    static func loadAll() -> [MailMessage] {
        let urls = Bundle.main.urls(forResourcesWithExtension: "json", subdirectory: nil) ?? []
        return urls.filter { $0.lastPathComponent.hasPrefix("email_") }.sorted { $0.lastPathComponent < $1.lastPathComponent }
            .compactMap { url in
                guard let data = try? Data(contentsOf: url) else { return nil }
                return try? JSONDecoder.feed.decode(MailMessage.self, from: data)
            }
    }
}
