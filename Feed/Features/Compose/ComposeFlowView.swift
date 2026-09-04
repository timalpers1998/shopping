import SwiftUI
import PhotosUI
import NukeUI

struct ComposeFlowView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(AppRouter.self) private var router
    @Environment(\.dismiss) private var dismiss
    @State private var model: ComposeViewModel?
    /// Called with the new post so the feed can show it immediately.
    var onPublished: (Post) -> Void

    var body: some View {
        NavigationStack {
            Group {
                if let model {
                    switch model.step {
                    case .account: CreateAuthorStep(model: model)
                    case .pick: PickStep(model: model)
                    case .preparing: VStack(spacing: 12) { ProgressView().tint(.white); Text("Preparing media…").foregroundStyle(.secondary) }
                    case .edit: EditStep(model: model)
                    case .publishing:
                        VStack(spacing: 16) {
                            ProgressView(value: model.progress).tint(.white).padding(.horizontal, 40)
                            Text("Posting… \(Int(model.progress * 100))%").foregroundStyle(.secondary)
                        }
                    case .done:
                        VStack(spacing: 12) {
                            Image(systemName: "checkmark.circle.fill").font(.system(size: 56)).foregroundStyle(.green)
                            Text("Posted").font(.title2.bold())
                        }
                        .accessibilityIdentifier("compose-done")
                        .task {
                            if let post = model.published { onPublished(post) }
                            try? await Task.sleep(for: .seconds(1))
                            dismiss()
                        }
                    }
                } else {
                    ProgressView().tint(.white)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.background)
            .foregroundStyle(.white)
            .navigationTitle("New post")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Theme.background, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.accessibilityIdentifier("compose-cancel") }
                if let model, model.step == .edit {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Post") { Task { await model.publish() } }.bold().disabled(!model.draft.canPublish).accessibilityIdentifier("compose-post")
                    }
                }
            }
        }
        .task { if model == nil { model = ComposeViewModel(environment: env) } }
        .preferredColorScheme(.dark)
    }
}

private struct CreateAuthorStep: View {
    @Bindable var model: ComposeViewModel
    var body: some View {
        VStack(spacing: 16) {
            Text("Pick your handle").font(.title2.bold())
            Text("This is how you'll appear on posts.").foregroundStyle(.secondary)
            TextField("handle", text: $model.handle).textInputAutocapitalization(.never).autocorrectionDisabled()
                .padding(14).background(Theme.surface, in: RoundedRectangle(cornerRadius: 12)).accessibilityIdentifier("author-handle")
            TextField("Display name", text: $model.displayName)
                .padding(14).background(Theme.surface, in: RoundedRectangle(cornerRadius: 12)).accessibilityIdentifier("author-name")
            if let e = model.error { Text(e).font(.footnote).foregroundStyle(.red) }
            Button { Task { await model.createAuthor() } } label: {
                Text("Continue").bold().frame(maxWidth: .infinity).frame(height: 50).background(.white, in: RoundedRectangle(cornerRadius: 12)).foregroundStyle(.black)
            }
            .disabled(model.handle.count < 2)
            Spacer()
        }
        .padding(20)
    }
}

private struct PickStep: View {
    @Bindable var model: ComposeViewModel
    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "photo.on.rectangle.angled").font(.system(size: 56)).foregroundStyle(.secondary)
            Text("Share a fit or a find").font(.title2.bold())
            Text("Up to 10 photos, or one video up to 60 seconds.").foregroundStyle(.secondary).multilineTextAlignment(.center)
            PhotosPicker(selection: $model.pickerItems, maxSelectionCount: 10, selectionBehavior: .ordered, matching: .any(of: [.images, .videos])) {
                Text("Choose from library").bold().frame(maxWidth: .infinity).frame(height: 50).background(.white, in: RoundedRectangle(cornerRadius: 12)).foregroundStyle(.black)
            }
            .accessibilityIdentifier("compose-pick")
            Spacer()
        }
        .padding(24)
        .onChange(of: model.pickerItems) { _, _ in Task { await model.prepareSelection() } }
    }
}

private struct EditStep: View {
    @Bindable var model: ComposeViewModel
    @FocusState private var urlFocused: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(model.draft.media) { m in
                            ZStack(alignment: .topTrailing) {
                                if let img = m.preview { Image(uiImage: img).resizable().scaledToFill() } else { Rectangle().fill(Theme.surface) }
                                if m.kind == .video { Image(systemName: "play.fill").padding(6).background(.black.opacity(0.5), in: Circle()).padding(4).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading) }
                                Button { model.removeMedia(m.id) } label: { Image(systemName: "xmark.circle.fill").font(.title3).foregroundStyle(.white, .black.opacity(0.6)) }.padding(4)
                            }
                            .frame(width: 120, height: 160).clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                        PhotosPicker(selection: $model.pickerItems, maxSelectionCount: 10, selectionBehavior: .ordered, matching: .any(of: [.images, .videos])) {
                            VStack { Image(systemName: "plus"); Text("Add").font(.caption) }.frame(width: 80, height: 160).background(Theme.surface, in: RoundedRectangle(cornerRadius: 10))
                        }
                    }
                }
                .onChange(of: model.pickerItems) { _, _ in Task { await model.prepareSelection() } }

                TextField("Write a caption…", text: $model.draft.caption, axis: .vertical)
                    .lineLimit(2...6)
                    .padding(12).background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))
                    .accessibilityIdentifier("compose-caption")

                VStack(alignment: .leading, spacing: 8) {
                    Text("Tag products").font(.headline)
                    HStack {
                        TextField("Paste a product link", text: $model.newProductURL)
                            .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                            .focused($urlFocused)
                            .onSubmit { model.addProductURL() }
                            .accessibilityIdentifier("compose-product-url")
                        Button { if let s = UIPasteboard.general.string { model.newProductURL = s }; model.addProductURL() } label: { Image(systemName: "doc.on.clipboard") }
                        Button("Add") { model.addProductURL() }.bold().disabled(model.newProductURL.isEmpty).accessibilityIdentifier("compose-add-product")
                    }
                    .padding(12).background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))
                    ForEach($model.draft.products) { $p in
                        ProductDraftRow(product: $p) { model.removeProduct(p.id) }
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Style").font(.headline)
                    FlowLayout(spacing: 8) {
                        ForEach(model.styleOptions, id: \.self) { tag in
                            let on = model.draft.styleTags.contains(tag)
                            Button(tag.replacingOccurrences(of: "_", with: " ")) { model.toggleStyle(tag) }
                                .font(.caption.bold()).padding(.horizontal, 12).padding(.vertical, 7)
                                .background(on ? .white : Theme.surface, in: Capsule()).foregroundStyle(on ? .black : .white)
                        }
                    }
                }

                Picker("For", selection: $model.draft.audience) {
                    Text("Everyone").tag("unisex"); Text("Women's").tag("womens"); Text("Men's").tag("mens")
                }
                .pickerStyle(.segmented)

                if let e = model.error { Text(e).font(.footnote).foregroundStyle(.red) }
            }
            .padding(16)
        }
        .scrollDismissesKeyboard(.interactively)
    }
}

private struct ProductDraftRow: View {
    @Binding var product: ProductDraft
    let onRemove: () -> Void
    @State private var priceText = ""

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            LazyImage(url: product.imageUrl.flatMap(URL.init(string:))) { state in
                if let image = state.image { image.resizable().scaledToFill() } else { Rectangle().fill(Theme.surfaceElevated).overlay(product.status == .scraping ? AnyView(ProgressView().tint(.white)) : AnyView(EmptyView())) }
            }
            .frame(width: 56, height: 56).clipShape(RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 6) {
                if product.status == .scraping {
                    Text("Fetching \(product.merchant)…").font(.caption).foregroundStyle(.secondary)
                } else {
                    TextField("Product name", text: $product.title).font(.subheadline.bold()).accessibilityIdentifier("product-title")
                    HStack(spacing: 8) {
                        TextField("Price", text: $priceText).keyboardType(.decimalPad).font(.caption).frame(width: 70)
                            .onChange(of: priceText) { _, v in product.priceCents = Double(v.replacingOccurrences(of: "$", with: "")).map { Int(($0 * 100).rounded()) } }
                        TextField("Brand", text: Binding(get: { product.brand ?? "" }, set: { product.brand = $0.isEmpty ? nil : $0 })).font(.caption)
                    }
                    Text(product.merchant).font(.caption2).foregroundStyle(.secondary)
                    if product.status == .manual { Text("Couldn't read this page; fill in the details.").font(.caption2).foregroundStyle(.orange) }
                }
            }
            Spacer(minLength: 0)
            Button(action: onRemove) { Image(systemName: "xmark").font(.caption.bold()).foregroundStyle(.secondary) }
        }
        .padding(10).background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))
        .onAppear { if let c = product.priceCents { priceText = String(format: c % 100 == 0 ? "%.0f" : "%.2f", Double(c) / 100) } }
        .onChange(of: product.priceCents) { _, c in if let c, priceText.isEmpty { priceText = String(format: c % 100 == 0 ? "%.0f" : "%.2f", Double(c) / 100) } }
    }
}

/// Minimal wrapping layout for chips.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 300
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0
        for s in subviews {
            let sz = s.sizeThatFits(.unspecified)
            if x + sz.width > width { x = 0; y += rowH + spacing; rowH = 0 }
            x += sz.width + spacing; rowH = max(rowH, sz.height)
        }
        return CGSize(width: width, height: y + rowH)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x: CGFloat = bounds.minX, y: CGFloat = bounds.minY, rowH: CGFloat = 0
        for s in subviews {
            let sz = s.sizeThatFits(.unspecified)
            if x + sz.width > bounds.maxX { x = bounds.minX; y += rowH + spacing; rowH = 0 }
            s.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
            x += sz.width + spacing; rowH = max(rowH, sz.height)
        }
    }
}
