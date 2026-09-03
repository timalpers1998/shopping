import SwiftUI
import NukeUI

struct ProductRailView: View {
    let post: Post
    let onTap: (Product) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(post.products) { product in
                    ProductCardView(product: product).onTapGesture { onTap(product) }
                }
            }
        }
    }
}

struct ProductCardView: View {
    let product: Product

    var body: some View {
        HStack(spacing: 10) {
            LazyImage(url: product.imageUrl) { state in
                if let image = state.image { image.resizable().scaledToFill() } else { Rectangle().fill(Theme.surfaceElevated) }
            }
            .pipeline(.feed)
            .processors([.resize(width: 160)])
            .frame(width: 52, height: 52)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 2) {
                Text(product.title).font(.caption.bold()).lineLimit(1)
                Text(product.brand ?? product.merchant).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                HStack(spacing: 4) {
                    if let price = PriceFormatter.string(cents: product.priceCents, currency: product.currency) {
                        Text(price).font(.caption.bold())
                    } else {
                        Text("See price").font(.caption)
                    }
                    Image(systemName: "arrow.up.right").font(.caption2.bold())
                }
                .foregroundStyle(Theme.accent)
            }
            .foregroundStyle(.white)
            Spacer(minLength: 0)
        }
        .padding(8)
        .frame(width: 210)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .contentShape(RoundedRectangle(cornerRadius: 12))
    }
}
