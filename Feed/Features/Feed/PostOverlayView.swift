import SwiftUI

struct PostOverlayView: View {
    let post: Post
    let model: FeedViewModel
    @Environment(AppRouter.self) private var router
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Button { router.feedPath.append(Route.profile(authorId: post.author.id)) } label: {
                    AvatarView(url: post.author.avatarUrl, size: 34)
                    HStack(spacing: 4) {
                        Text(post.author.handle).font(.subheadline.bold())
                        if post.author.isVerified { Image(systemName: "checkmark.seal.fill").font(.caption).foregroundStyle(.cyan) }
                        if post.author.kind == .brand { Text("Brand").font(.caption2.bold()).padding(.horizontal, 6).padding(.vertical, 2).background(.white.opacity(0.2), in: Capsule()) }
                    }
                }
                .buttonStyle(.plain)
                if !post.author.isFollowing {
                    Button("Follow") { model.toggleFollow(post) }
                        .font(.caption.bold())
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .overlay(Capsule().stroke(.white, lineWidth: 1))
                        .buttonStyle(.plain)
                }
                Text(RelativeDate.short(post.createdAt)).font(.caption).foregroundStyle(Theme.textSecondary)
            }
            .foregroundStyle(.white)

            if !post.caption.isEmpty {
                Text(post.caption)
                    .font(.subheadline)
                    .foregroundStyle(.white)
                    .lineLimit(expanded ? nil : 2)
                    .onTapGesture { withAnimation(.snappy) { expanded.toggle() } }
            }

            if !post.products.isEmpty {
                ProductRailView(post: post) { product in model.openProduct(product, in: post) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .shadow(color: .black.opacity(0.5), radius: 4, y: 1)
    }
}

struct ActionRailView: View {
    let post: Post
    let model: FeedViewModel
    @Environment(AppRouter.self) private var router

    var body: some View {
        VStack(spacing: 18) {
            rail(id: "like-button", label: post.viewer.liked ? "Unlike" : "Like", icon: post.viewer.liked ? "heart.fill" : "heart", tint: post.viewer.liked ? .red : .white, count: post.stats.likes) {
                model.toggleLike(post)
            }
            rail(id: "comments-button", label: "Comments", icon: "bubble.right", tint: .white, count: post.stats.comments) {
                router.present(.comments(postId: post.id))
            }
            rail(id: "save-button", label: post.viewer.saved ? "Unsave" : "Save", icon: post.viewer.saved ? "bookmark.fill" : "bookmark", tint: post.viewer.saved ? .yellow : .white, count: post.stats.saves) {
                model.toggleSave(post)
            }
            ShareLink(item: post.products.first?.url ?? URL(string: "https://example.com")!) {
                VStack(spacing: 3) {
                    Image(systemName: "arrowshape.turn.up.right").font(.system(size: 26, weight: .semibold))
                    Text("Share").font(.caption2.bold())
                }
                .foregroundStyle(.white)
            }
        }
        .padding(.bottom, 4)
        .shadow(color: .black.opacity(0.5), radius: 4, y: 1)
    }

    private func rail(id: String, label: String, icon: String, tint: Color, count: Int, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: icon).font(.system(size: 28, weight: .semibold)).foregroundStyle(tint)
                    .contentTransition(.symbolEffect(.replace))
                Text(CountFormatter.compact(count)).font(.caption2.bold()).foregroundStyle(.white)
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
        .accessibilityLabel(label)
        .accessibilityValue(String(count))
        .sensoryFeedback(.impact(weight: .light), trigger: count)
    }
}
