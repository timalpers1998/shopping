import Foundation
import Observation

@MainActor
@Observable
final class PurchaseImportViewModel {
    enum Step: Equatable { case intro, connecting, scanning, enriching, review, applying, done, failed(String) }

    struct BrandGroup: Identifiable {
        let name: String
        var items: [PurchaseItem]
        var id: String { name }
        var includedCount: Int { items.filter(\.included).count }
        var medianPrice: Int? {
            let p = items.compactMap(\.priceCents).sorted()
            return p.isEmpty ? nil : p[p.count / 2]
        }
    }

    private let env: AppEnvironment
    let providers: [MailProvider]
    var step: Step = .intro
    var progress = ScanProgress()
    private(set) var account: MailAccount?
    private(set) var orders: [ParsedOrder] = []
    var setPriceBand = true
    var followBrands = true
    private(set) var result: PurchaseApplyResult?
    private var provider: MailProvider?
    private var scanTask: Task<Void, Never>?

    init(environment: AppEnvironment) {
        self.env = environment
        self.providers = environment.mailProviders.filter(\.isAvailable)
    }

    var groups: [BrandGroup] {
        let pairs = orders.flatMap { o in o.items.map { (o.merchantBrand ?? $0.brand ?? o.merchant, $0) } }
        let g = Dictionary(grouping: pairs, by: { $0.0 })
        return g.map { BrandGroup(name: $0.key, items: $0.value.map(\.1)) }.sorted { ($0.items.count, $0.name) > ($1.items.count, $1.name) }
    }
    var includedItemCount: Int { orders.reduce(0) { $0 + $1.items.filter(\.included).count } }
    var ordersFound: Int { orders.count }
    var medianPriceCents: Int? {
        let p = orders.flatMap { $0.items.filter(\.included) }.compactMap(\.priceCents).sorted()
        return p.isEmpty ? nil : p[p.count / 2]
    }
    var priceBandLabel: String? {
        guard let c = medianPriceCents else { return nil }
        switch c { case ..<5000: return "Under $50"; case ..<15000: return "$50–150"; case ..<50000: return "$150–500"; default: return "$500+" }
    }

    func connect(_ provider: MailProvider) {
        self.provider = provider
        step = .connecting
        scanTask = Task {
            do {
                account = try await provider.connect()
                step = .scanning
                var found: [ParsedOrder] = []
                let stream = provider.scan { [weak self] p in Task { @MainActor in self?.progress = p } }
                for try await message in stream {
                    if let order = PurchaseParser.parse(message) { found.append(order) }
                }
                orders = PurchaseParser.dedupe(found)
                // "Other" category is off by default; it would drag the taste vector.
                for o in orders.indices { for i in orders[o].items.indices where orders[o].items[i].category == nil { orders[o].items[i].included = false } }
                step = .enriching
                await enrichImages()
                await provider.disconnect()
                step = .review
            } catch is CancellationError {
                await provider.disconnect(); step = .intro
            } catch OAuthError.cancelled {
                await provider.disconnect(); step = .intro
            } catch {
                await provider.disconnect(); step = .failed(error.localizedDescription)
            }
        }
    }

    /// Fills missing item images via the product link scraper (signed-in users only; fixtures always).
    private func enrichImages() async {
        for o in orders.indices {
            for i in orders[o].items.indices where orders[o].items[i].imageUrl == nil {
                guard let url = orders[o].items[i].productUrl else { continue }
                if let img = await env.purchaseRepository.scrapeImage(url: url) { orders[o].items[i].imageUrl = img }
            }
        }
    }

    func cancel() {
        scanTask?.cancel()
        step = .intro
    }

    func toggleBrand(_ name: String, on: Bool) {
        for o in orders.indices {
            for i in orders[o].items.indices where (orders[o].merchantBrand ?? orders[o].items[i].brand ?? orders[o].merchant) == name {
                orders[o].items[i].included = on
            }
        }
    }

    func toggleItem(_ id: UUID) {
        for o in orders.indices { if let i = orders[o].items.firstIndex(where: { $0.id == id }) { orders[o].items[i].included.toggle() } }
    }

    func apply() {
        guard let account else { return }
        step = .applying
        Task {
            do {
                result = try await env.purchaseRepository.apply(provider: account.kind, accountLabel: account.label, scanned: progress.total,
                                                                  orders: orders, setPriceBand: setPriceBand, followBrands: followBrands)
                await env.refreshMe()
                step = .done
            } catch {
                step = .failed(error.localizedDescription)
            }
        }
    }
}
