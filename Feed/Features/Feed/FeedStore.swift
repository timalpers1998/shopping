import Foundation
import Observation

/// Items, cursor and scroll position for one category feed.
@MainActor
@Observable
final class FeedStore {
    let category: FeedCategory
    private let repository: FeedRepository
    private let sessionId: UUID
    private let pageSize: Int

    private(set) var items: [Post] = []
    private(set) var nextCursor: String?
    private(set) var isLoading = false
    private(set) var hasMore = true
    private(set) var error: String?
    private(set) var loadedAt: Date?
    private(set) var requestId: String?
    var currentPostID: UUID?
    private var seenIds = Set<UUID>()
    private var inflight: Task<Void, Never>?

    init(category: FeedCategory, repository: FeedRepository, sessionId: UUID, pageSize: Int = 10) {
        self.category = category
        self.repository = repository
        self.sessionId = sessionId
        self.pageSize = pageSize
    }

    var currentIndex: Int? { currentPostID.flatMap { id in items.firstIndex { $0.id == id } } }

    func loadInitialIfNeeded() async {
        guard items.isEmpty, loadedAt == nil else { return }
        await refresh()
    }

    func refresh() async {
        inflight?.cancel()
        nextCursor = nil
        hasMore = true
        error = nil
        seenIds.removeAll()
        await load(replace: true)
    }

    func loadMoreIfNeeded(currentIndex: Int) {
        guard hasMore, !isLoading, currentIndex >= items.count - 3 else { return }
        inflight = Task { await load(replace: false) }
    }

    private func load(replace: Bool) async {
        isLoading = true
        defer { isLoading = false }
        do {
            let page = try await repository.fetchFeed(category: category, sessionId: sessionId, cursor: replace ? nil : nextCursor, limit: pageSize)
            guard !Task.isCancelled else { return }
            let fresh = page.items.filter { seenIds.insert($0.id).inserted }
            if replace {
                items = fresh
                currentPostID = fresh.first?.id
            } else {
                items.append(contentsOf: fresh)
            }
            nextCursor = page.nextCursor
            hasMore = page.nextCursor != nil
            requestId = page.requestId
            loadedAt = Date()
            error = nil
        } catch {
            if !Task.isCancelled { self.error = error.localizedDescription }
        }
    }

    func update(_ post: Post) {
        if let i = items.firstIndex(where: { $0.id == post.id }) { items[i] = post }
    }

    func mutate(_ id: UUID, _ change: (inout Post) -> Void) {
        if let i = items.firstIndex(where: { $0.id == id }) { change(&items[i]) }
    }
}
