import Foundation
import Observation

@MainActor
@Observable
final class ProfileViewModel {
    let authorId: UUID
    private let env: AppEnvironment
    private(set) var profile: AuthorProfile?
    private(set) var isLoading = false
    private(set) var error: String?

    init(authorId: UUID, environment: AppEnvironment) {
        self.authorId = authorId
        self.env = environment
    }

    func load() async {
        guard profile == nil else { return }
        isLoading = true; defer { isLoading = false }
        do { profile = try await env.profileRepository.authorProfile(id: authorId); error = nil }
        catch { self.error = error.localizedDescription }
    }

    func loadMore() async {
        guard var p = profile, let cursor = p.nextCursor, !isLoading else { return }
        isLoading = true; defer { isLoading = false }
        if let page = try? await env.profileRepository.authorPosts(id: authorId, cursor: cursor) {
            p.posts += page.items; p.nextCursor = page.nextCursor; profile = p
        }
    }

    func toggleFollow() {
        guard var p = profile else { return }
        let following = !p.author.isFollowing
        p.author.isFollowing = following
        p.author.followerCount = max(0, (p.author.followerCount ?? 0) + (following ? 1 : -1))
        profile = p
        guard !env.usingFixtures else { return }
        Task {
            do {
                let r = try await env.socialRepository.toggleFollow(authorId: authorId)
                profile?.author.isFollowing = r.active; profile?.author.followerCount = r.count
            } catch {
                profile?.author.isFollowing = !following
            }
        }
    }
}

@MainActor
@Observable
final class OwnProfileViewModel {
    private let env: AppEnvironment
    private(set) var posts: [Post] = []
    private(set) var saved: [Post] = []
    private(set) var savedCursor: String?
    private(set) var isLoading = false
    var tab: Tab = .posts
    enum Tab: String, CaseIterable { case posts = "Posts", saved = "Saved" }

    init(environment: AppEnvironment) { self.env = environment }

    func load() async {
        isLoading = true; defer { isLoading = false }
        async let savedPage = env.profileRepository.savedPosts(cursor: nil)
        if let author = env.me?.primaryAuthor, let profile = try? await env.profileRepository.authorProfile(id: author.id) {
            posts = profile.posts
        } else {
            posts = []
        }
        if let page = try? await savedPage { saved = page.items; savedCursor = page.nextCursor }
    }
}
