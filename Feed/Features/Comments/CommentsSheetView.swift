import SwiftUI

@MainActor
@Observable
final class CommentsViewModel {
    let postId: UUID
    private let env: AppEnvironment
    private(set) var comments: [Comment] = []
    private(set) var nextCursor: String?
    private(set) var isLoading = false
    private(set) var error: String?
    var draft = ""
    var onCountChange: ((Int) -> Void)?

    init(postId: UUID, environment: AppEnvironment) { self.postId = postId; self.env = environment }

    func load() async {
        isLoading = true; defer { isLoading = false }
        do {
            let page = try await env.commentRepository.comments(postId: postId, cursor: nil)
            comments = page.items; nextCursor = page.nextCursor; error = nil
        } catch { self.error = error.localizedDescription }
    }

    func loadMore() async {
        guard let cursor = nextCursor, !isLoading else { return }
        isLoading = true; defer { isLoading = false }
        if let page = try? await env.commentRepository.comments(postId: postId, cursor: cursor) {
            comments += page.items; nextCursor = page.nextCursor
        }
    }

    func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        guard env.requireAccount(for: "comment") else { return }
        draft = ""
        let temp = Comment(id: UUID(), postId: postId, author: Author(id: env.me?.id ?? UUID(), handle: env.me?.username ?? "you", displayName: env.me?.displayName ?? "You", avatarUrl: env.me?.avatarUrl, kind: .creator), text: text, createdAt: Date(), isPending: true)
        comments.append(temp)
        onCountChange?(1)
        Task {
            do {
                let real = try await env.commentRepository.add(postId: postId, text: text)
                if let i = comments.firstIndex(where: { $0.id == temp.id }) { comments[i] = real }
            } catch {
                comments.removeAll { $0.id == temp.id }
                onCountChange?(-1)
                self.error = error.localizedDescription
            }
        }
    }

    func delete(_ comment: Comment) {
        comments.removeAll { $0.id == comment.id }
        onCountChange?(-1)
        Task { try? await env.commentRepository.delete(commentId: comment.id) }
    }
}

struct CommentsSheetView: View {
    let postId: UUID
    let onCountChange: (Int) -> Void
    @Environment(AppEnvironment.self) private var env
    @State private var model: CommentsViewModel?
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            Text("Comments").font(.headline).padding(.vertical, 12)
            Divider().overlay(.white.opacity(0.1))
            if let model {
                if model.comments.isEmpty && !model.isLoading {
                    EmptyStateView(icon: "bubble.right", title: "No comments yet", message: "Say something nice.")
                } else {
                    List {
                        ForEach(model.comments) { c in
                            CommentRowView(comment: c)
                                .listRowBackground(Theme.background)
                                .listRowSeparator(.hidden)
                                .swipeActions {
                                    if c.author.id == env.me?.id { Button("Delete", role: .destructive) { model.delete(c) } }
                                }
                                .onAppear { if c.id == model.comments.last?.id { Task { await model.loadMore() } } }
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
                if let error = model.error { Text(error).font(.caption).foregroundStyle(.red) }
                HStack(spacing: 10) {
                    AvatarView(url: env.me?.avatarUrl, size: 32)
                    TextField("Add a comment…", text: Bindable(model).draft, axis: .vertical)
                        .lineLimit(1...4)
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(Theme.surface, in: Capsule())
                        .focused($focused)
                        .accessibilityIdentifier("comment-field")
                    Button { model.send() } label: { Image(systemName: "arrow.up.circle.fill").font(.title) }
                        .disabled(model.draft.trimmingCharacters(in: .whitespaces).isEmpty)
                        .accessibilityIdentifier("comment-send")
                }
                .padding(12)
            } else {
                ProgressView().tint(.white).frame(maxHeight: .infinity)
            }
        }
        .background(Theme.background)
        .foregroundStyle(.white)
        .task {
            if model == nil {
                let m = CommentsViewModel(postId: postId, environment: env)
                m.onCountChange = onCountChange
                model = m
            }
            await model?.load()
        }
    }
}

struct CommentRowView: View {
    let comment: Comment
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            AvatarView(url: comment.author.avatarUrl, size: 32)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(comment.author.handle).font(.caption.bold())
                    Text(RelativeDate.short(comment.createdAt)).font(.caption2).foregroundStyle(.secondary)
                }
                Text(comment.text).font(.subheadline)
            }
            Spacer(minLength: 0)
        }
        .opacity(comment.isPending ? 0.5 : 1)
        .padding(.vertical, 4)
    }
}
