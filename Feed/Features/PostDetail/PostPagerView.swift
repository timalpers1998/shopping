import SwiftUI

/// Payload for pushing a feed-style pager over a fixed set of posts (profile grid, saved tab).
struct PostPagerPayload: Hashable {
    let posts: [Post]
    let startIndex: Int
}

struct PostPagerView: View {
    let payload: PostPagerPayload
    @Environment(AppEnvironment.self) private var env
    @State private var model: FeedViewModel?

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            if let model {
                FeedPagerView(store: model.store, model: model)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .overlay(alignment: .topLeading) { BackButton().padding(.leading, 8) }
        .task {
            if model == nil {
                let m = FeedViewModel(environment: env)
                m.installStatic(posts: payload.posts, startAt: payload.startIndex)
                model = m
            }
        }
        .onDisappear { model?.isVisible = false }
    }
}

struct BackButton: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        Button { dismiss() } label: {
            Image(systemName: "chevron.left").font(.title3.bold()).foregroundStyle(.white).padding(10)
                .background(.black.opacity(0.35), in: Circle())
        }
        .accessibilityIdentifier("back-button")
    }
}
