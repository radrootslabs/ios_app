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
        startStream(app: app)
    }

    func onDisappear(app: AppState) {
        liveTask?.cancel()
        liveTask = nil
        Task { try? app.radroots.nostrStopPostStream() }
    }

    func load(app: AppState) async {
        guard let rt = app.radroots.runtime else { return }
        isLoading = true
        errorMessage = nil
        do {
            let fetched = try rt.nostrFetchTextNotes(limit: 50, sinceUnix: nil)
            posts = fetched.sorted { $0.publishedAt > $1.publishedAt }
            isLoading = false
        } catch {
            errorMessage = String(describing: error)
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
        guard let rt = app.radroots.runtime else { return }
        let raw = draftReplies[post.id, default: ""]
        let reply = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !reply.isEmpty else { return }
        sendingReplyFor.insert(post.id)

        Task { @MainActor in
            let runtime = rt
            let parentId = post.id
            let parentAuthor = post.author
            let text = reply

            let result: Result<String, Error> = await Task.detached { @Sendable in
                do {
                    let id = try runtime.nostrPostReply(
                        parentEventIdHex: parentId,
                        parentAuthorHex: parentAuthor,
                        content: text,
                        rootEventIdHex: nil as String?
                    )
                    return .success(id)
                } catch {
                    return .failure(error)
                }
            }.value

            switch result {
            case .success(let id):
                draftReplies[parentId] = ""
                expandedReplyFor = nil
                sendingReplyFor.remove(parentId)
                setResult("Reply Posted", "Event \(id)")
            case .failure(let e):
                sendingReplyFor.remove(parentId)
                setResult("Failed to Post Reply", String(describing: e))
            }
        }
    }


    private func startStream(app: AppState) {
        guard liveTask == nil else { return }
        liveTask = Task { @MainActor [weak self] in
            guard let self else { return }
            var knownIds = Set(posts.map(\.id))
            let since = posts.map(\.publishedAt).max()
            do {
                try app.radroots.nostrStartPostStream(sinceUnix: since)
            } catch {
                errorMessage = String(describing: error)
            }

            while !Task.isCancelled {
                if app.relayConnectedCount == 0 {
                    try? await Task.sleep(for: .seconds(1))
                    continue
                }

                if knownIds.count != posts.count {
                    knownIds = Set(posts.map(\.id))
                }

                if let event = app.radroots.nostrNextPostStreamEvent() {
                    if knownIds.insert(event.id).inserted {
                        posts.insert(event, at: 0)
                        posts.sort { $0.publishedAt > $1.publishedAt }
                        if posts.count > 200 {
                            posts = Array(posts.prefix(200))
                        }
                    }
                } else {
                    try? await Task.sleep(for: .milliseconds(300))
                }
            }
        }
    }
}
