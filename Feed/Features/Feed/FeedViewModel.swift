import Foundation
import Observation

@MainActor
@Observable
final class FeedViewModel {
    private let env: AppEnvironment
    private(set) var stores: [FeedCategory: FeedStore] = [:]
    var selectedCategory: FeedCategory = .forYou
    var isVisible = true {
        didSet {
            guard isVisible != oldValue else { return }
            if isVisible { resumeImpression(); if let id = store.currentPostID { players.resume(id) } }
            else { impressions.end(); players.pauseAll() }
        }
    }

    let impressions: ImpressionTracker
    let players = VideoPlayerPool()
    private let prefetcher = FeedPrefetcher()

    init(environment: AppEnvironment) {
        self.env = environment
        self.impressions = environment.makeImpressionTracker()
        players.onLoop = { [weak self] id in self?.videoLooped(id) }
    }

    private func videoLooped(_ postId: UUID) {
        guard let post = store.items.first(where: { $0.id == postId }) else { return }
        track(.videoComplete, post: post)
    }

    /// Video players for the active post and its neighbours.
    private func syncPlayers(in store: FeedStore, index: Int) {
        let window = max(0, index - 1)...min(store.items.count - 1, index + 1)
        let keep = store.items[window].compactMap { p -> (id: UUID, url: URL)? in
            guard p.kind == .video, let url = p.media.first?.url else { return nil }
            return (p.id, url)
        }
        players.assign(keep: keep, active: isVisible ? store.currentPostID : nil)
    }

    var store: FeedStore { store(for: selectedCategory) }

    /// Use this model as a pager over a fixed list of posts (profile grid, saved tab).
    func installStatic(posts: [Post], startAt index: Int) {
        let s = FeedStore(category: .forYou, repository: StaticFeedRepository(posts: posts), sessionId: env.sessionId, pageSize: max(posts.count, 1))
        s.installStatic(posts: posts, startAt: index)
        stores[.forYou] = s
        selectedCategory = .forYou
    }

    func store(for category: FeedCategory) -> FeedStore {
        if let s = stores[category] { return s }
        let s = FeedStore(category: category, repository: env.feedRepository, sessionId: env.sessionId)
        stores[category] = s
        return s
    }

    func select(_ category: FeedCategory) {
        guard category != selectedCategory else {
            Task { await store.refresh() }
            return
        }
        impressions.end()
        players.pauseAll()
        selectedCategory = category
        Task {
            let s = store(for: category)
            if let loadedAt = s.loadedAt, Date().timeIntervalSince(loadedAt) > 15 * 60 {
                await s.refresh()
            } else {
                await s.loadInitialIfNeeded()
            }
            resumeImpression()
        }
    }

    /// Called when the pager's active post changes.
    func activePostChanged(in store: FeedStore) {
        guard store.category == selectedCategory, let index = store.currentIndex else { return }
        let post = store.items[index]
        if isVisible { impressions.begin(post: post, index: index, category: store.category) }
        store.loadMoreIfNeeded(currentIndex: index)
        prefetcher.update(posts: store.items, currentIndex: index)
        syncPlayers(in: store, index: index)
    }

    private func resumeImpression() {
        guard isVisible, let index = store.currentIndex else { return }
        impressions.begin(post: store.items[index], index: index, category: store.category)
    }

    // MARK: actions (optimistic; persisted from M3)

    func toggleLike(_ post: Post) {
        let liked = !post.viewer.liked
        setLiked(post.id, liked, delta: liked ? 1 : -1)
        if env.usingFixtures { track(liked ? .like : .unlike, post: post); return }
        Task {
            do {
                let r = try await env.socialRepository.toggleLike(postId: post.id)
                for s in stores.values { s.mutate(post.id) { p in p.viewer.liked = r.active; p.stats.likes = r.count } }
            } catch {
                setLiked(post.id, !liked, delta: liked ? -1 : 1)
            }
        }
    }

    func toggleSave(_ post: Post) {
        let saved = !post.viewer.saved
        setSaved(post.id, saved, delta: saved ? 1 : -1)
        if env.usingFixtures { track(saved ? .save : .unsave, post: post); return }
        Task {
            do {
                let r = try await env.socialRepository.toggleSave(postId: post.id)
                for s in stores.values { s.mutate(post.id) { p in p.viewer.saved = r.active; p.stats.saves = r.count } }
            } catch {
                setSaved(post.id, !saved, delta: saved ? -1 : 1)
            }
        }
    }

    func toggleFollow(_ post: Post) {
        let following = !post.author.isFollowing
        setFollowing(post.author.id, following)
        if env.usingFixtures { track(following ? .follow : .unfollow, post: post); return }
        Task {
            do {
                let r = try await env.socialRepository.toggleFollow(authorId: post.author.id)
                setFollowing(post.author.id, r.active)
            } catch {
                setFollowing(post.author.id, !following)
            }
        }
    }

    /// A freshly published post shows up at the top of Following (and For You in fixtures mode).
    func insertNewPost(_ post: Post) {
        store(for: .following).prepend(post)
        if env.usingFixtures { store(for: .forYou).prepend(post) }
    }

    func adjustCommentCount(postId: UUID, by delta: Int) {
        for s in stores.values { s.mutate(postId) { p in p.stats.comments = max(0, p.stats.comments + delta) } }
    }

    private func setLiked(_ id: UUID, _ liked: Bool, delta: Int) {
        for s in stores.values { s.mutate(id) { p in p.viewer.liked = liked; p.stats.likes = max(0, p.stats.likes + delta) } }
    }
    private func setSaved(_ id: UUID, _ saved: Bool, delta: Int) {
        for s in stores.values { s.mutate(id) { p in p.viewer.saved = saved; p.stats.saves = max(0, p.stats.saves + delta) } }
    }
    private func setFollowing(_ authorId: UUID, _ following: Bool) {
        for s in stores.values {
            for item in s.items where item.author.id == authorId { s.mutate(item.id) { p in p.author.isFollowing = following } }
        }
    }

    func openProduct(_ product: Product, in post: Post) {
        let url = env.clickOut.url(for: product, in: post, position: store.currentIndex)
        env.router.openProduct(url)
    }

    private func track(_ type: EventType, post: Post) {
        let e = AnalyticsEvent(type: type, sessionId: env.sessionId, postId: post.id, authorId: post.author.id, category: post.category, position: store.currentIndex)
        Task { await env.eventTracker.track(e) }
    }
}
