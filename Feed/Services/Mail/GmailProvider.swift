import Foundation

/// Reads likely order emails from Gmail on the device. Three passes: id search, metadata classification, full fetch.
final class GmailProvider: MailProvider, @unchecked Sendable {
    let kind: MailProviderKind = .gmail
    private let clientId: String?
    private let session: URLSession
    private var token: OAuthTokenSet?
    private var accountEmail = ""
    private let keychainAccount = "gmail"

    init(clientId: String?) {
        self.clientId = clientId
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 30
        session = URLSession(configuration: cfg)
    }

    var isAvailable: Bool { clientId != nil }

    func connect() async throws -> MailAccount {
        guard let clientId else { throw OAuthError.tokenExchange("Gmail is not configured") }
        let client = await OAuthClient(config: .google(clientId: clientId))
        let t = try await client.authorize()
        token = t
        if let data = try? JSONEncoder().encode(t) { KeychainStore.save(data, account: keychainAccount) }
        accountEmail = Self.email(fromIdToken: t.idToken) ?? "gmail"
        return MailAccount(kind: .gmail, label: accountEmail.maskedEmail)
    }

    func disconnect() async {
        if let clientId, let token {
            await OAuthClient(config: .google(clientId: clientId)).revoke(token)
        }
        token = nil
        KeychainStore.delete(account: keychainAccount)
    }

    private static let merchantDomains = MerchantCatalog.shared.domains
    private static let subjectTerms = "\"order confirmation\" OR \"order confirmed\" OR \"your order\" OR \"thanks for your order\" OR \"thank you for your order\" OR \"order receipt\" OR \"your receipt\" OR \"receipt for\" OR \"has shipped\" OR \"your shipment\" OR \"on its way\" OR \"order #\" OR \"order number\""

    private var queries: [String] {
        var q = [
            "category:purchases newer_than:2y -in:spam -in:trash",
            "newer_than:2y -in:spam -in:trash subject:(\(Self.subjectTerms)) -subject:(unsubscribe OR newsletter OR \"% off\")",
        ]
        // Sender-domain queries in chunks of ~40 domains.
        let domains = Self.merchantDomains
        var i = 0
        while i < domains.count {
            let chunk = domains[i..<min(i + 40, domains.count)]
            q.append("newer_than:2y -in:spam -in:trash from:(\(chunk.joined(separator: " OR ")))")
            i += 40
        }
        return q
    }

    func scan(progress: @escaping @Sendable (ScanProgress) -> Void) -> AsyncThrowingStream<MailMessage, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    var ids: [String] = []
                    var seen = Set<String>()
                    for q in queries {
                        var page: String? = nil
                        repeat {
                            let list: MessageList = try await get("messages", query: ["q": q, "maxResults": "100", "pageToken": page ?? ""])
                            for m in list.messages ?? [] where seen.insert(m.id).inserted { ids.append(m.id) }
                            page = list.nextPageToken
                        } while page != nil && ids.count < 800
                        if ids.count >= 800 { break }
                    }
                    var p = ScanProgress(scanned: 0, total: ids.count)
                    progress(p)
                    try await withThrowingTaskGroup(of: MailMessage?.self) { group in
                        var iterator = ids.makeIterator()
                        var inflight = 0
                        func addNext() {
                            if let id = iterator.next() {
                                inflight += 1
                                group.addTask { [self] in try await self.fetchIfCandidate(id: id) }
                            }
                        }
                        for _ in 0..<6 { addNext() }
                        for try await msg in group {
                            inflight -= 1
                            p.scanned += 1
                            progress(p)
                            if let msg { continuation.yield(msg) }
                            addNext()
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    // MARK: Gmail REST

    private struct MessageList: Decodable { struct Ref: Decodable { let id: String }; let messages: [Ref]?; let nextPageToken: String? }
    private struct Header: Decodable { let name: String; let value: String }
    private struct Body: Decodable { let data: String?; let size: Int? }
    private struct Part: Decodable { let mimeType: String?; let headers: [Header]?; let body: Body?; let parts: [Part]? }
    private struct Message: Decodable { let id: String; let internalDate: String?; let payload: Part? }

    private func fetchIfCandidate(id: String) async throws -> MailMessage? {
        let meta: Message = try await get("messages/\(id)", query: ["format": "metadata", "metadataHeaders": "From", "metadataHeaders": "Subject"])
        let from = meta.payload?.headers?.first { $0.name.lowercased() == "from" }?.value ?? ""
        let subject = meta.payload?.headers?.first { $0.name.lowercased() == "subject" }?.value ?? ""
        guard OrderClassifier.classify(subject: subject, from: from) != .notAnOrder else { return nil }
        let full: Message = try await get("messages/\(id)", query: ["format": "full"])
        var html: String? = nil, text: String? = nil
        Self.walk(full.payload, html: &html, text: &text)
        let date = Date(timeIntervalSince1970: (Double(full.internalDate ?? "") ?? 0) / 1000)
        let (name, addr) = Self.splitFrom(from)
        return MailMessage(id: id, provider: .gmail, fromAddress: addr, fromName: name, subject: subject, receivedAt: date, html: html, text: text)
    }

    private static func walk(_ part: Part?, html: inout String?, text: inout String?) {
        guard let part else { return }
        if let data = part.body?.data, let decoded = decodeBase64URL(data) {
            if part.mimeType == "text/html", html == nil { html = decoded }
            else if part.mimeType == "text/plain", text == nil { text = decoded }
        }
        for p in part.parts ?? [] { walk(p, html: &html, text: &text) }
    }

    private static func decodeBase64URL(_ s: String) -> String? {
        var b = s.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while b.count % 4 != 0 { b += "=" }
        return Data(base64Encoded: b).flatMap { String(data: $0, encoding: .utf8) }
    }

    private static func splitFrom(_ from: String) -> (String?, String) {
        if let lt = from.firstIndex(of: "<"), let gt = from.firstIndex(of: ">") {
            let name = from[..<lt].trimmingCharacters(in: CharacterSet(charactersIn: " \"")).nilIfEmpty
            return (name, String(from[from.index(after: lt)..<gt]).lowercased())
        }
        return (nil, from.lowercased())
    }

    private static func email(fromIdToken token: String?) -> String? {
        guard let token else { return nil }
        let parts = token.split(separator: ".")
        guard parts.count >= 2, let payload = decodeBase64URL(String(parts[1])), let data = payload.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return json["email"] as? String
    }

    private func get<T: Decodable>(_ path: String, query: KeyValuePairs<String, String>) async throws -> T {
        var attempt = 0
        while true {
            var t = try await validToken()
            var comps = URLComponents(string: "https://gmail.googleapis.com/gmail/v1/users/me/\(path)")!
            comps.queryItems = query.filter { !$0.value.isEmpty }.map { URLQueryItem(name: $0.key, value: $0.value) }
            var req = URLRequest(url: comps.url!)
            req.setValue("Bearer \(t.accessToken)", forHTTPHeaderField: "Authorization")
            let (data, resp) = try await session.data(for: req)
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            if code == 200 { return try JSONDecoder().decode(T.self, from: data) }
            if code == 401, attempt == 0, let clientId {
                t = try await OAuthClient(config: .google(clientId: clientId)).refresh(t)
                token = t
                attempt += 1
                continue
            }
            if (code == 429 || code == 403 || code >= 500) && attempt < 4 {
                attempt += 1
                try await Task.sleep(for: .milliseconds(Int(pow(2.0, Double(attempt))) * 500 + Int.random(in: 0...300)))
                continue
            }
            throw OAuthError.tokenExchange("Gmail returned \(code)")
        }
    }

    private func validToken() async throws -> OAuthTokenSet {
        if token == nil, let data = KeychainStore.load(account: keychainAccount) { token = try? JSONDecoder().decode(OAuthTokenSet.self, from: data) }
        guard var t = token else { throw OAuthError.tokenExchange("not connected") }
        if t.isExpiringSoon, let clientId { t = try await OAuthClient(config: .google(clientId: clientId)).refresh(t); token = t }
        return t
    }
}

private extension String { var nilIfEmpty: String? { isEmpty ? nil : self } }
