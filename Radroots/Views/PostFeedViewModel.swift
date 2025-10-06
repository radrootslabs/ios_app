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
        if posts.isEmpty {
            Task { await load(app: app) }
        }
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


    private func startLiveLoop(app: AppState) {
        guard liveTask == nil else { return }
        liveTask = Task { @MainActor [weak self] in
            guard let self else { return }
            var knownIds = Set(posts.map(\.id))
            var since = posts.map(\.publishedAt).max()

            while !Task.isCancelled {
                if app.relayConnectedCount == 0 {
                    try? await Task.sleep(for: .seconds(2))
                    continue
                }
                guard let rt = app.radroots.runtime else {
                    try? await Task.sleep(for: .seconds(2))
                    continue
                }

                let currentSince = since
                let fetchResult: Result<[NostrPostEventMetadata], Error> = await Task.detached { @Sendable in
                    do {
                        let items = try rt.nostrFetchTextNotes(limit: 50, sinceUnix: currentSince)
                        return .success(items)
                    } catch {
                        return .failure(error)
                    }
                }.value

                if Task.isCancelled { break }

                switch fetchResult {
                case .failure:
                    break
                case .success(let fetched):
                    let newOnes = fetched.filter { !knownIds.contains($0.id) }
                    if !newOnes.isEmpty {
                        knownIds.formUnion(newOnes.map(\.id))
                        let maxTs = newOnes.map(\.publishedAt).max()
                        posts = (newOnes + posts).sorted { $0.publishedAt > $1.publishedAt }
                        if let m = maxTs {
                            since = max(since ?? 0, m)
                        }
                    }
                }

                try? await Task.sleep(for: .seconds(3))
            }
        }
    }
}
