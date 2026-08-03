import SwiftUI

@MainActor
final class PostFeedViewModel: ObservableObject {
    @Published var posts: [NostrPostEventMetadata] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var expandedReplyFor: String?
    @Published var draftReplies: [String: String] = [:]
    @Published var sendingReplyFor: Set<String> = []

    private var liveTask: Task<Void, Never>?

    func onAppear(app: AppState) {
        if posts.isEmpty {
            Task { await load(app: app) }
        }
        startPolling(app: app)
    }

    func onDisappear(app: AppState) {
        liveTask?.cancel()
        liveTask = nil
    }

    func load(app: AppState) async {
        guard let service = app.runtimeService else { return }
        isLoading = true
        errorMessage = nil
        do {
            let fetched = try await service.nostrFetchTextNotes(limit: 50, sinceUnix: nil)
            posts = fetched.sorted { $0.publishedAt > $1.publishedAt }
            isLoading = false
        } catch {
            errorMessage = error.fieldRuntimeMessage
            isLoading = false
        }
    }

    func refresh(app: AppState) async {
        await load(app: app)
    }

    func toggleReply(for id: String) {
        expandedReplyFor = expandedReplyFor == id ? nil : id
    }

    func bindingForReply(_ id: String) -> Binding<String> {
        Binding(
            get: { self.draftReplies[id, default: ""] },
            set: { self.draftReplies[id] = $0 }
        )
    }

    func sendReply(
        app: AppState,
        to post: NostrPostEventMetadata,
        setResult: @escaping @MainActor @Sendable (_ title: String, _ message: String) -> Void
    ) {
        guard let service = app.runtimeService else { return }
        let raw = draftReplies[post.id, default: ""]
        let reply = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !reply.isEmpty else { return }
        sendingReplyFor.insert(post.id)

        Task { @MainActor in
            let parentId = post.id
            let parentAuthor = post.author
            let text = reply

            do {
                let id = try await service.nostrPostReply(
                        parentEventIdHex: parentId,
                        parentAuthorHex: parentAuthor,
                        content: text,
                        rootEventIdHex: nil as String?
                    )
                draftReplies[parentId] = ""
                expandedReplyFor = nil
                sendingReplyFor.remove(parentId)
                setResult("Reply Posted", "Event \(id.rawValue)")
            } catch {
                sendingReplyFor.remove(parentId)
                setResult("Failed to Post Reply", error.fieldRuntimeMessage)
            }
        }
    }


    private func startPolling(app: AppState) {
        guard liveTask == nil else { return }
        liveTask = Task { @MainActor [weak self] in
            guard let self else { return }
            guard let service = app.runtimeService else { return }
            while !Task.isCancelled {
                if !app.relaySourceAvailable {
                    try? await Task.sleep(for: .seconds(2))
                    continue
                }

                do {
                    let since = posts.map(\.publishedAt).max()
                    let fetched = try await service.nostrFetchTextNotes(limit: 50, sinceUnix: since)
                    let knownIds = Set(posts.map(\.id))
                    let newPosts = fetched.filter { !knownIds.contains($0.id) }
                    if !newPosts.isEmpty {
                        posts.append(contentsOf: newPosts)
                        posts.sort { $0.publishedAt > $1.publishedAt }
                        posts = Array(posts.prefix(200))
                    }
                    errorMessage = nil
                } catch {
                    errorMessage = error.fieldRuntimeMessage
                }
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }
}
