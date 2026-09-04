import SwiftUI
import NukeUI

/// "Import what you already buy": connect a mailbox, scan on-device, review a grid of purchases, apply to taste.
struct PurchaseImportFlowView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    @State private var model: PurchaseImportViewModel?
    var onDone: (Bool) -> Void

    var body: some View {
        NavigationStack {
            Group {
                if let model {
                    switch model.step {
                    case .intro: IntroView(model: model) { finish(applied: false) }
                    case .connecting: status("Connecting…", detail: "Finish signing in with your mail provider.")
                    case .scanning: ScanningView(model: model)
                    case .enriching: status("Finding product photos…", detail: "\(model.ordersFound) orders found")
                    case .review: ReviewView(model: model) { finish(applied: false) }
                    case .applying: status("Adding to your taste…", detail: nil)
                    case .done:
                        VStack(spacing: 12) {
                            Image(systemName: "checkmark.circle.fill").font(.system(size: 56)).foregroundStyle(.green)
                            Text("Added \(model.result?.items ?? 0) items").font(.title2.bold())
                            Text("Your feed will adjust over the next few minutes.").foregroundStyle(.secondary)
                        }
                        .accessibilityIdentifier("import-done")
                        .task { try? await Task.sleep(for: .seconds(1.2)); finish(applied: true) }
                    case .failed(let msg):
                        VStack(spacing: 12) {
                            Text("Couldn't import").font(.title3.bold())
                            Text(msg).font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                            Button("Try again") { model.step = .intro }.buttonStyle(.borderedProminent).tint(.white).foregroundStyle(.black)
                            Button("Skip") { finish(applied: false) }.foregroundStyle(.secondary)
                        }.padding()
                    }
                } else { ProgressView().tint(.white) }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.background)
            .foregroundStyle(.white)
            .navigationTitle("Your purchases")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Theme.background, for: .navigationBar)
        }
        .task { if model == nil { model = PurchaseImportViewModel(environment: env) } }
        .preferredColorScheme(.dark)
        .interactiveDismissDisabled()
    }

    private func finish(applied: Bool) { onDone(applied) }

    private func status(_ title: String, detail: String?) -> some View {
        VStack(spacing: 12) {
            ProgressView().tint(.white)
            Text(title).font(.headline)
            if let detail { Text(detail).font(.footnote).foregroundStyle(.secondary) }
        }
    }
}

private struct IntroView: View {
    @Bindable var model: PurchaseImportViewModel
    let onSkip: () -> Void
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Image(systemName: "bag.badge.plus").font(.system(size: 44)).foregroundStyle(.white)
                Text("Import what you already buy").font(.title.bold())
                Text("Connect your inbox and Feed looks through order confirmations, receipts and shipping emails from the last two years to learn the brands, products and price range you actually buy.")
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 8) {
                    Label("Reading happens on your phone. Your emails never leave it.", systemImage: "iphone")
                    Label("We keep only a list of items: brand, product, price, date and photo.", systemImage: "list.bullet.rectangle")
                    Label("You review the list before anything is saved, and can delete it any time.", systemImage: "trash")
                }
                .font(.subheadline)
                Spacer(minLength: 12)
                ForEach(Array(model.providers.enumerated()), id: \.offset) { _, provider in
                    Button { model.connect(provider) } label: {
                        Label(provider.kind == .gmail ? "Connect Gmail" : provider.kind == .outlook ? "Connect Outlook" : "Connect sample inbox",
                              systemImage: "envelope")
                            .bold().frame(maxWidth: .infinity).frame(height: 50)
                            .background(.white, in: RoundedRectangle(cornerRadius: 12)).foregroundStyle(.black)
                    }
                    .accessibilityIdentifier("import-connect-\(provider.kind.rawValue)")
                }
                if model.providers.isEmpty {
                    Text("No mail provider is configured on this build yet.").font(.footnote).foregroundStyle(.secondary)
                }
                Button("Not now", action: onSkip).frame(maxWidth: .infinity).foregroundStyle(.secondary).accessibilityIdentifier("import-skip")
            }
            .padding(24)
        }
    }
}

private struct ScanningView: View {
    @Bindable var model: PurchaseImportViewModel
    var body: some View {
        VStack(spacing: 16) {
            ProgressView(value: model.progress.total == 0 ? 0 : Double(model.progress.scanned), total: Double(max(model.progress.total, 1))).tint(.white).padding(.horizontal, 40)
            Text("Looking through your inbox…").font(.headline)
            Text("Scanned \(model.progress.scanned) of \(model.progress.total) emails").font(.footnote).foregroundStyle(.secondary)
            Text("Nothing has been uploaded.").font(.caption).foregroundStyle(.secondary)
            Button("Cancel") { model.cancel() }.foregroundStyle(.secondary).padding(.top, 8)
        }
    }
}

private struct ReviewView: View {
    @Bindable var model: PurchaseImportViewModel
    let onSkip: () -> Void
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 3)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(model.includedItemCount) items from \(model.groups.count) brands").font(.title2.bold())
                    Text("Tap to include or exclude. Only what's selected is saved.").font(.footnote).foregroundStyle(.secondary)
                }
                if model.orders.isEmpty {
                    EmptyStateView(icon: "tray", title: "No orders found", message: "We couldn't find shopping emails in the last two years.").frame(height: 260)
                }
                ForEach(model.groups) { group in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(group.name).font(.headline)
                            Text("\(group.items.count)").font(.caption).foregroundStyle(.secondary)
                            if let m = group.medianPrice, let s = PriceFormatter.string(cents: m, currency: "USD") { Text("· \(s) median").font(.caption).foregroundStyle(.secondary) }
                            Spacer()
                            Toggle("", isOn: Binding(get: { group.includedCount > 0 }, set: { model.toggleBrand(group.name, on: $0) })).labelsHidden().tint(.green)
                                .accessibilityIdentifier("import-brand-\(group.name)")
                        }
                        LazyVGrid(columns: columns, spacing: 6) {
                            ForEach(group.items) { item in
                                PurchaseTile(item: item).onTapGesture { model.toggleItem(item.id) }
                                    .accessibilityIdentifier("import-item-\(item.title)")
                            }
                        }
                    }
                }
                if let band = model.priceBandLabel {
                    Toggle(isOn: $model.setPriceBand) { Text("Set my price range to \(band)").font(.subheadline) }.tint(.green).accessibilityIdentifier("import-price-band-toggle")
                }
                Toggle(isOn: $model.followBrands) { Text("Follow these brands on Feed").font(.subheadline) }.tint(.green)
                Button { model.apply() } label: {
                    Text("Add to my taste").bold().frame(maxWidth: .infinity).frame(height: 52)
                        .background(.white, in: RoundedRectangle(cornerRadius: 14)).foregroundStyle(.black)
                }
                .disabled(model.includedItemCount == 0)
                .accessibilityIdentifier("import-apply")
                Button("Skip", action: onSkip).frame(maxWidth: .infinity).foregroundStyle(.secondary)
            }
            .padding(20)
        }
    }
}

struct PurchaseTile: View {
    let item: PurchaseItem
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ZStack(alignment: .topTrailing) {
                Color.clear
                    .aspectRatio(3/4, contentMode: .fit)
                    .overlay {
                        LazyImage(url: item.imageUrl.flatMap(URL.init(string:))) { state in
                            if let image = state.image { image.resizable().scaledToFill() } else { Rectangle().fill(Theme.surfaceElevated).overlay(Image(systemName: "bag").foregroundStyle(.secondary)) }
                        }
                        .pipeline(.feed)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                Image(systemName: item.included ? "checkmark.circle.fill" : "circle").font(.title3).foregroundStyle(.white, item.included ? .blue : .black.opacity(0.4)).padding(6)
            }
            Text(item.title).font(.caption2).lineLimit(2)
            if let p = PriceFormatter.string(cents: item.priceCents, currency: item.currency) { Text(p).font(.caption2.bold()).foregroundStyle(.secondary) }
        }
        .opacity(item.included ? 1 : 0.45)
    }
}

/// Settings → Imported purchases.
struct ImportedPurchasesView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(AppRouter.self) private var router
    @State private var summary: PurchaseImportsSummary?
    @State private var confirmDelete = false
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 3)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let summary {
                    if summary.imports.isEmpty {
                        EmptyStateView(icon: "envelope", title: "Not connected", message: "Import your past orders to tune your feed.", actionTitle: "Import purchases") { router.present(.purchaseImport) }
                            .frame(height: 320)
                    } else {
                        ForEach(summary.imports) { imp in
                            HStack {
                                VStack(alignment: .leading) { Text(imp.accountLabel ?? imp.provider).font(.subheadline.bold()); Text("\(imp.items) items · \(RelativeDate.short(imp.createdAt)) ago").font(.caption).foregroundStyle(.secondary) }
                                Spacer()
                            }
                            .padding(12).background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))
                        }
                        if let band = summary.priceBand, summary.priceBandSource == "purchases" { Text("Price range set from purchases: \(band)").font(.footnote).foregroundStyle(.secondary) }
                        LazyVGrid(columns: columns, spacing: 6) {
                            ForEach(summary.items) { it in
                                PurchaseTile(item: PurchaseItem(title: it.title, brand: it.brand, priceCents: it.priceCents, currency: it.currency, category: it.category, imageUrl: it.imageUrl, productUrl: it.productUrl))
                            }
                        }
                        Button("Import again") { router.present(.purchaseImport) }.frame(maxWidth: .infinity)
                        Button("Delete imported purchases", role: .destructive) { confirmDelete = true }.frame(maxWidth: .infinity).accessibilityIdentifier("import-delete")
                    }
                } else { ProgressView().tint(.white).frame(maxWidth: .infinity) }
            }
            .padding(16)
        }
        .background(Theme.background)
        .navigationTitle("Imported purchases")
        .navigationBarTitleDisplayMode(.inline)
        .task { summary = try? await env.purchaseRepository.summary() }
        .refreshable { summary = try? await env.purchaseRepository.summary() }
        .confirmationDialog("Delete imported purchases?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { Task { try? await env.purchaseRepository.deleteAll(); await env.refreshMe(); summary = try? await env.purchaseRepository.summary() } }
                .accessibilityIdentifier("import-delete-confirm")
        } message: { Text("This removes all imported items and the price range and taste they set. Brands you followed stay followed.") }
    }
}
