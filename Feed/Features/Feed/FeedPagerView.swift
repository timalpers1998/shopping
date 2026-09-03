import SwiftUI

/// TikTok-style vertical pager. Cells are full-screen; the active cell is whichever `scrollPosition` reports.
struct FeedPagerView: View {
    @Bindable var store: FeedStore
    let model: FeedViewModel

    var body: some View {
        GeometryReader { geo in
            ScrollView(.vertical) {
                LazyVStack(spacing: 0) {
                    ForEach(Array(store.items.enumerated()), id: \.element.id) { index, post in
                        PostCellView(post: post, index: index, isActive: post.id == store.currentPostID, model: model)
                            .frame(width: geo.size.width, height: geo.size.height)
                            .id(post.id)
                    }
                    if store.isLoading && !store.items.isEmpty {
                        ProgressView().tint(.white).frame(width: geo.size.width, height: geo.size.height)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: $store.currentPostID)
            .scrollIndicators(.hidden)
        }
        .ignoresSafeArea()
        .onChange(of: store.currentPostID) { _, _ in model.activePostChanged(in: store) }
    }
}
