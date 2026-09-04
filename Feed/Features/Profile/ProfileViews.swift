import SwiftUI

/// Another creator's or brand's profile.
struct ProfileView: View {
    let authorId: UUID
    @Environment(AppEnvironment.self) private var env
    @Environment(AppRouter.self) private var router
    @State private var model: ProfileViewModel?

    var body: some View {
        Group {
            if let model, let profile = model.profile {
                ScrollView {
                    ProfileHeaderView(author: profile.author, isOwn: false) { model.toggleFollow() }
                    PostGridView(posts: profile.posts) { index in
                        router.feedPath.append(Route.pager(PostPagerPayload(posts: profile.posts, startIndex: index)))
                    } onReachEnd: { Task { await model.loadMore() } }
                }
                .background(Theme.background)
            } else if let model, let error = model.error {
                ErrorStateView(message: error) { Task { await model.load() } }
            } else {
                ProgressView().tint(.white).frame(maxWidth: .infinity, maxHeight: .infinity).background(Theme.background)
            }
        }
        .navigationTitle(model?.profile?.author.handle ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Theme.background, for: .navigationBar)
        .task {
            if model == nil { model = ProfileViewModel(authorId: authorId, environment: env) }
            await model?.load()
        }
    }
}

/// The user's own tab: posts (if they have a creator account) and saved posts.
struct OwnProfileView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(AppRouter.self) private var router
    @State private var model: OwnProfileViewModel?

    var body: some View {
        ScrollView {
            if let me = env.me {
                if let author = me.primaryAuthor {
                    ProfileHeaderView(author: author, isOwn: true) {}
                } else {
                    VStack(spacing: 8) {
                        AvatarView(url: me.avatarUrl, size: 84)
                        Text(me.isAnonymous ? "Guest" : (me.displayName ?? "You")).font(.title3.bold())
                        if me.isAnonymous {
                            Text("Sign in to keep your saves and post your own finds.").font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                            Button("Sign in") { router.present(.auth(reason: "keep your saves")) }
                                .buttonStyle(.borderedProminent).tint(.white).foregroundStyle(.black)
                                .accessibilityIdentifier("profile-sign-in")
                        }
                    }
                    .padding(.top, 24)
                }
            }
            if let model {
                Picker("", selection: Bindable(model).tab) {
                    ForEach(OwnProfileViewModel.Tab.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented).padding(.horizontal, 40).padding(.vertical, 12)
                let items = model.tab == .posts ? model.posts : model.saved
                if items.isEmpty && !model.isLoading {
                    EmptyStateView(icon: model.tab == .posts ? "square.grid.2x2" : "bookmark",
                                   title: model.tab == .posts ? "No posts yet" : "Nothing saved yet",
                                   message: model.tab == .posts ? "Tap + to share your first find." : "Tap the bookmark on posts you want to come back to.")
                        .frame(height: 320)
                } else {
                    PostGridView(posts: items) { index in
                        router.profilePath.append(Route.pager(PostPagerPayload(posts: items, startIndex: index)))
                    } onReachEnd: {}
                }
            }
        }
        .background(Theme.background)
        .navigationTitle("Profile")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink(value: Route.settings) { Image(systemName: "line.3.horizontal") }
                    .accessibilityIdentifier("profile-settings")
            }
        }
        .toolbarBackground(Theme.background, for: .navigationBar)
        .task {
            if model == nil { model = OwnProfileViewModel(environment: env) }
            await model?.load()
        }
        .refreshable { await env.refreshMe(); await model?.load() }
    }
}

struct ProfileHeaderView: View {
    let author: Author
    let isOwn: Bool
    let onFollow: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            AvatarView(url: author.avatarUrl, size: 84)
            HStack(spacing: 6) {
                Text(author.displayName).font(.title3.bold())
                if author.isVerified { Image(systemName: "checkmark.seal.fill").foregroundStyle(.cyan) }
            }
            Text("@\(author.handle)").font(.subheadline).foregroundStyle(.secondary)
            HStack(spacing: 28) {
                stat(author.postCount ?? 0, "Posts")
                stat(author.followerCount ?? 0, "Followers")
            }
            if let bio = author.bio, !bio.isEmpty { Text(bio).font(.footnote).multilineTextAlignment(.center).padding(.horizontal, 32) }
            if !isOwn {
                Button(author.isFollowing ? "Following" : "Follow", action: onFollow)
                    .font(.subheadline.bold())
                    .frame(width: 160, height: 40)
                    .background(author.isFollowing ? Theme.surfaceElevated : .white, in: RoundedRectangle(cornerRadius: 10))
                    .foregroundStyle(author.isFollowing ? .white : .black)
                    .accessibilityIdentifier("follow-button")
            }
        }
        .padding(.top, 16)
        .foregroundStyle(.white)
    }

    private func stat(_ n: Int, _ label: String) -> some View {
        VStack(spacing: 2) { Text(CountFormatter.compact(n)).font(.headline); Text(label).font(.caption).foregroundStyle(.secondary) }
    }
}

struct PostGridView: View {
    let posts: [Post]
    let onTap: (Int) -> Void
    let onReachEnd: () -> Void
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 3)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 2) {
            ForEach(Array(posts.enumerated()), id: \.element.id) { index, post in
                PostGridCell(post: post)
                    .onTapGesture { onTap(index) }
                    .onAppear { if index == posts.count - 3 { onReachEnd() } }
            }
        }
        .padding(.top, 8)
    }
}

struct PostGridCell: View {
    let post: Post
    var body: some View {
        GeometryReader { geo in
            FeedImage(url: post.coverURL, isPortrait: true)
                .frame(width: geo.size.width, height: geo.size.height)
        }
        .aspectRatio(3/4, contentMode: .fit)
        .clipped()
        .overlay(alignment: .topTrailing) {
            if post.kind != .image {
                Image(systemName: post.kind == .video ? "play.fill" : "square.on.square").font(.caption.bold()).padding(6).foregroundStyle(.white).shadow(radius: 2)
            }
        }
        .overlay(alignment: .bottomLeading) {
            Label(CountFormatter.compact(post.stats.likes), systemImage: "heart.fill").font(.caption2.bold()).padding(6).foregroundStyle(.white).shadow(radius: 2)
        }
    }
}
