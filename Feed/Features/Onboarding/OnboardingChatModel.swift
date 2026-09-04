import Foundation
import Observation

/// One conversation that replaces the quiz screens and the purchase-import screens.
/// The assistant asks; the user answers with the one control that fits the question.
@MainActor
@Observable
final class OnboardingChatModel {
    enum Input: Equatable {
        case name, audience, budget, styles, brands, inbox, review, finish
    }

    enum Item: Identifiable, Equatable {
        case assistant(id: UUID, text: String)
        case user(id: UUID, text: String)
        case typing(id: UUID)
        case thinking(id: UUID, text: String)
        case input(id: UUID, Input)
        case profile(id: UUID, TasteSummary)

        var id: UUID {
            switch self {
            case .assistant(let id, _), .user(let id, _), .typing(let id), .thinking(let id, _), .input(let id, _), .profile(let id, _): id
            }
        }
    }

    struct TasteSummary: Equatable {
        var name: String
        var audience: String
        var band: String
        var styles: [String]
        var brands: [String]
        var importedItems: Int
        var importedBrands: [String]
    }

    private let env: AppEnvironment
    var purchases: PurchaseImportViewModel
    private(set) var items: [Item] = []
    private(set) var catalog: QuizCatalog?
    var name = ""
    var answers = QuizAnswers()
    private(set) var finished = false
    private var thinkingId: UUID?
    private var purchaseObserver: Task<Void, Never>?

    init(environment: AppEnvironment) {
        self.env = environment
        self.purchases = PurchaseImportViewModel(environment: environment)
        if let n = environment.me?.displayName, !n.isEmpty, n != "You" { name = n }
    }

    var hasInbox: Bool { !purchases.providers.isEmpty }
    var styleLabel: (String) -> String { { slug in self.catalog?.styles.first { $0.slug == slug }?.label ?? slug.replacingOccurrences(of: "_", with: " ").capitalized } }
    var brandName: (UUID) -> String { { id in self.catalog?.brands.first { $0.id == id }?.name ?? "" } }

    // MARK: flow

    func start() async {
        catalog = try? await env.tasteRepository.catalog()
        let hour = Calendar.current.component(.hour, from: Date())
        let greeting = hour < 12 ? "Good morning." : hour < 18 ? "Good afternoon." : "Good evening."
        await say("\(greeting) I'm Feed. I learn what you actually like to buy, so the more you scroll, the better it gets.")
        if name.isEmpty {
            await say("What should I call you?", delay: 0.5)
            ask(.name)
        } else {
            await say("Nice to see you, \(name). Two quick questions, then I'll show you things you'll want.", delay: 0.5)
            ask(.audience)
        }
    }

    func submitName() {
        let n = name.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty else { return }
        name = n
        answer(n)
        Task {
            try? await env.profileRepository.updateDisplayName(n)
            await say("Nice to meet you, \(n). Who are you shopping for?")
            ask(.audience)
        }
    }

    func submitAudience(_ value: String, label: String) {
        answers.audience = value
        answer(label)
        Task {
            await say("And what do you usually spend on a piece? This is a lean, not a limit.")
            ask(.budget)
        }
    }

    func submitBudget(_ value: String, label: String) {
        answers.priceBand = value
        answer(label)
        Task {
            await say("Pick a few looks you'd actually wear. Three or more.")
            ask(.styles)
        }
    }

    func toggleStyle(_ slug: String) {
        if answers.styles.contains(slug) { answers.styles.remove(slug) } else { answers.styles.insert(slug) }
    }

    func submitStyles() {
        guard answers.styles.count >= 3 else { return }
        let names = answers.styles.map(styleLabel).sorted()
        answer(names.joined(separator: ", "))
        Task {
            await say("Any brands you already love? Skip if nothing jumps out.")
            ask(.brands)
        }
    }

    func toggleBrand(_ id: UUID) {
        if answers.brandIds.contains(id) { answers.brandIds.remove(id) } else { answers.brandIds.insert(id) }
    }

    func submitBrands() {
        let names = answers.brandIds.map(brandName).filter { !$0.isEmpty }.sorted()
        answer(names.isEmpty ? "None yet" : names.joined(separator: ", "))
        Task {
            try? await env.tasteRepository.submit(answers)
            await env.refreshMe()
            if hasInbox {
                await say("Last thing. If you connect your inbox, I'll read your order emails on this phone and learn from what you already buy. Only the item list is kept, and you can delete it any time.")
                ask(.inbox)
            } else {
                await finishUp()
            }
        }
    }

    func connect(_ provider: MailProvider) {
        answer(provider.kind == .fixture ? "Connect sample inbox" : "Connect Gmail")
        purchases.connect(provider)
        observePurchases()
    }

    func skipInbox() {
        answer("Not now")
        Task { await finishUp() }
    }

    private func observePurchases() {
        purchaseObserver?.cancel()
        purchaseObserver = Task { [weak self] in
            var lastStep: PurchaseImportViewModel.Step? = nil
            while let self, !Task.isCancelled {
                let step = purchases.step
                if step != lastStep {
                    lastStep = step
                    switch step {
                    case .connecting: think("Connecting…")
                    case .scanning: think("Looking through your inbox…")
                    case .enriching: think("Finding product photos…")
                    case .review:
                        clearThinking()
                        if purchases.orders.isEmpty {
                            await say("I couldn't find shopping emails from the last two years, so we'll start from your picks.")
                            await finishUp()
                        } else {
                            await say("I found \(purchases.includedItemCount) items from \(purchases.groups.count) brands. Tap anything you'd rather I ignore.")
                            ask(.review)
                        }
                        return
                    case .intro:
                        clearThinking(); await say("No problem, we'll start from your picks."); await finishUp(); return
                    case .failed(let msg):
                        clearThinking(); await say("That didn't work: \(msg). We'll start from your picks."); await finishUp(); return
                    default: break
                    }
                } else if step == .scanning {
                    think("Looking through your inbox… \(purchases.progress.scanned) of \(purchases.progress.total)")
                }
                try? await Task.sleep(for: .milliseconds(200))
            }
        }
    }

    func applyPurchases() {
        answer("Add \(purchases.includedItemCount) items to my taste")
        think("Adding to your taste…")
        purchases.apply()
        Task {
            while purchases.step == .applying { try? await Task.sleep(for: .milliseconds(150)) }
            clearThinking()
            await finishUp()
        }
    }

    func skipPurchases() {
        answer("Skip these")
        Task { await finishUp() }
    }

    private func finishUp() async {
        let bandLabel = ["budget": "under $50", "mid": "$50–150", "premium": "$150–500", "luxury": "$500+"][answers.priceBand] ?? answers.priceBand
        let imported = purchases.step == .done ? purchases.includedItemCount : 0
        let summary = TasteSummary(name: name.isEmpty ? "Your" : "\(name)'s", audience: answers.audience, band: bandLabel,
                                   styles: answers.styles.map(styleLabel).sorted(), brands: answers.brandIds.map(brandName).filter { !$0.isEmpty }.sorted(),
                                   importedItems: imported, importedBrands: imported > 0 ? purchases.groups.filter { $0.includedCount > 0 }.map(\.name) : [])
        await say("Here's what I'll start from. It keeps updating as you scroll, like, save and buy.")
        items.append(.profile(id: UUID(), summary))
        ask(.finish)
    }

    func finish() {
        UserDefaults.standard.set(true, forKey: "onboarding.shown")
        finished = true
    }

    // MARK: helpers

    private func say(_ text: String, delay: Double = 0.9) async {
        let typing = UUID()
        items.append(.typing(id: typing))
        try? await Task.sleep(for: .seconds(delay))
        items.removeAll { $0.id == typing }
        items.append(.assistant(id: UUID(), text: text))
    }

    private func ask(_ input: Input) {
        items.append(.input(id: UUID(), input))
    }

    private func answer(_ text: String) {
        items.removeAll { if case .input = $0 { return true } else { return false } }
        items.append(.user(id: UUID(), text: text))
    }

    private func think(_ text: String) {
        if let id = thinkingId, let i = items.firstIndex(where: { $0.id == id }) {
            items[i] = .thinking(id: id, text: text)
        } else {
            let id = UUID(); thinkingId = id
            items.append(.thinking(id: id, text: text))
        }
    }

    private func clearThinking() {
        if let id = thinkingId { items.removeAll { $0.id == id }; thinkingId = nil }
    }
}
