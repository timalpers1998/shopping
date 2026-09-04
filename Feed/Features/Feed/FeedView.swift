import SwiftUI

struct FeedView: View {
    @Bindable var model: FeedViewModel
    @Environment(AppRouter.self) private var router

    var body: some View {
        ZStack(alignment: .top) {
            Theme.background.ignoresSafeArea()
            content
            CategoryChipsBar(selected: model.selectedCategory) { model.select($0) }
                .padding(.top, 4)
        }
        .toolbar(.hidden, for: .navigationBar)
        .task { await model.store.loadInitialIfNeeded(); model.activePostChanged(in: model.store) }
        .onAppear { model.isVisible = router.feedPath.isEmpty && router.selectedTab == .feed }
        .onDisappear { model.isVisible = false }
    }

    @ViewBuilder
    private var content: some View {
        let store = model.store
        if store.items.isEmpty {
            if store.isLoading {
                FeedSkeletonView()
            } else if let error = store.error {
                ErrorStateView(message: error) { Task { await store.refresh() } }
            } else if store.category == .following {
                EmptyStateView(icon: "person.2", title: "Nothing here yet", message: "Follow creators and brands to see their posts here.")
            } else {
                EmptyStateView(icon: "sparkles", title: "Nothing here yet", message: "Pull to refresh in a moment.")
            }
        } else {
            FeedPagerView(store: store, model: model)
                .id(store.category)
        }
    }
}

struct FeedSkeletonView: View {
    var body: some View {
        ZStack {
            Theme.surface
            VStack(alignment: .leading, spacing: 10) {
                Spacer()
                RoundedRectangle(cornerRadius: 6).fill(Theme.surfaceElevated).frame(width: 160, height: 14)
                RoundedRectangle(cornerRadius: 6).fill(Theme.surfaceElevated).frame(width: 260, height: 14)
                HStack { ForEach(0..<3, id: \.self) { _ in RoundedRectangle(cornerRadius: 10).fill(Theme.surfaceElevated).frame(width: 150, height: 64) } }
            }
            .padding(16)
            .padding(.bottom, 90)
        }
        .ignoresSafeArea()
        .shimmer()
    }
}
