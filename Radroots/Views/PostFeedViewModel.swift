import SwiftUI
import RadrootsKit

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
        if posts.isEmpty { Task { await load(app: app) } }
        startLiveLoop(app: app)
    }

    func onDisappear() {
        liveTask?.cancel()
        liveTask = nil
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
        setResult: @escaping (_ title: String, _ message: String) -> Void
    ) {
        guard let rt = app.radroots.runtime else { return }
        let raw = draftReplies[post.id, default: ""]
        let reply = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !reply.isEmpty else { return }
        sendingReplyFor.insert(post.id)

        Task {
            do {
                let id = try rt.nostrPostReply(
                    parentEventIdHex: post.id,
                    parentAuthorHex: post.author,
                    content: reply,
                    rootEventIdHex: nil as String?
                )
                draftReplies[post.id] = ""
                expandedReplyFor = nil
                sendingReplyFor.remove(post.id)
                setResult("Reply Posted", "Event \(id)")
            } catch {
                sendingReplyFor.remove(post.id)
                setResult("Failed to Post Reply", String(describing: error))
            }
        }
    }

    private func startLiveLoop(app: AppState) {
        guard liveTask == nil else { return }
        liveTask = Task { [weak self] in
            guard let self else { return }
            var known = Set(posts.map { $0.id })
            var since: UInt64? = posts.first?.publishedAt
            while !Task.isCancelled {
                if app.relayConnectedCount == 0 {
                    try? await Task.sleep(for: .seconds(2))
                    continue
                }
                guard let rt = app.radroots.runtime else {
                    try? await Task.sleep(for: .seconds(2))
                    continue
                }
                do {
                    let fetched = try rt.nostrFetchTextNotes(limit: 50, sinceUnix: since)
                    let newOnes = fetched.filter { !known.contains($0.id) }
                    if !newOnes.isEmpty {
                        known.formUnion(newOnes.map { $0.id })
                        let combined = (newOnes + posts).sorted { $0.publishedAt > $1.publishedAt }
                        posts = combined
                        if let m = newOnes.map(\.publishedAt).max() {
                            since = max(since ?? 0, m)
                        }
                    }
                } catch { }
                try? await Task.sleep(for: .seconds(3))
            }
        }
    }
}
