import SwiftUI
import NukeUI

@MainActor
@Observable
final class DiscoverViewModel {
    private let env: AppEnvironment
    var query = ""
    private(set) var results: [Post] = []
    private(set) var trending: [TrendingProduct] = []
    private(set) var isSearching = false
    private var task: Task<Void, Never>?

    init(environment: AppEnvironment) { self.env = environment }

    func loadTrending() async {
        if trending.isEmpty { trending = (try? await env.discoverRepository.trending()) ?? [] }
    }

    func queryChanged() {
        task?.cancel()
        let q = query.trimmingCharacters(in: .whitespaces)
        guard q.count >= 2 else { results = []; isSearching = false; return }
        task = Task {
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            isSearching = true
            results = (try? await env.discoverRepository.search(q)) ?? []
            isSearching = false
        }
    }

    func open(_ product: TrendingProduct) {
        let post = Post(id: product.postId ?? UUID(), kind: .image, caption: "", createdAt: Date(), category: "fashion", author: Author(id: UUID(), handle: product.merchant, displayName: product.brand ?? product.merchant, kind: .brand), media: [], products: [])
        let p = Product(id: product.id, title: product.title, imageUrl: product.imageUrl, priceCents: product.priceCents, currency: product.currency, merchant: product.merchant, brand: product.brand, url: product.url, redirectId: product.redirectId)
        env.router.openProduct(env.clickOut.url(for: p, in: post, position: nil))
    }
}

struct DiscoverView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(AppRouter.self) private var router
    @State private var model: DiscoverViewModel?
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 2)

    var body: some View {
        ScrollView {
            if let model {
                @Bindable var model = model
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                        TextField("Search brands, products, styles", text: $model.query)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                            .onChange(of: model.query) { _, _ in model.queryChanged() }
                            .accessibilityIdentifier("discover-search")
                        if !model.query.isEmpty { Button { model.query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) } }
                    }
                    .padding(12).background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))

                    if model.query.trimmingCharacters(in: .whitespaces).count >= 2 {
                        if model.isSearching && model.results.isEmpty {
                            ProgressView().tint(.white).frame(maxWidth: .infinity)
                        } else if model.results.isEmpty {
                            EmptyStateView(icon: "magnifyingglass", title: "No matches", message: "Try a brand, a garment, or a style like \"scandi\".").frame(height: 260)
                        } else {
                            Text("\(model.results.count) posts").font(.caption).foregroundStyle(.secondary)
                            PostGridView(posts: model.results) { index in
                                router.feedPath.append(Route.pager(PostPagerPayload(posts: model.results, startIndex: index)))
                            } onReachEnd: {}
                        }
                    } else {
                        Text("Trending products").font(.headline)
                        LazyVGrid(columns: columns, spacing: 10) {
                            ForEach(model.trending) { p in
                                Button { model.open(p) } label: {
                                    VStack(alignment: .leading, spacing: 6) {
                                        LazyImage(url: p.imageUrl) { state in
                                            if let image = state.image { image.resizable().scaledToFill() } else { Rectangle().fill(Theme.surfaceElevated) }
                                        }
                                        .pipeline(.feed)
                                        .aspectRatio(3/4, contentMode: .fill)
                                        .clipShape(RoundedRectangle(cornerRadius: 12))
                                        Text(p.title).font(.caption.bold()).lineLimit(2).foregroundStyle(.white)
                                        HStack {
                                            Text(p.brand ?? p.merchant).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                                            Spacer()
                                            if let s = PriceFormatter.string(cents: p.priceCents, currency: p.currency) { Text(s).font(.caption.bold()).foregroundStyle(Theme.accent) }
                                        }
                                    }
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("trending-\(p.title)")
                            }
                        }
                    }
                }
                .padding(16)
            }
        }
        .background(Theme.background)
        .foregroundStyle(.white)
        .navigationTitle("Discover")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Theme.background, for: .navigationBar)
        .scrollDismissesKeyboard(.immediately)
        .task {
            if model == nil { model = DiscoverViewModel(environment: env) }
            await model?.loadTrending()
        }
    }
}
