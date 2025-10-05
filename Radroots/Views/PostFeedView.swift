import SwiftUI
import RadrootsKit

struct PostFeedView: View {
    @EnvironmentObject private var app: AppState
    @State private var posts: [NostrPostEventMetadata] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        List {
            if let e = errorMessage {
                Section {
                    Text(e).foregroundStyle(.red).font(.footnote)
                }
            }
            Section {
                ForEach(posts, id: \.id) { item in
                    NavigationLink {
                        PostDetailView(post: item)
                    } label: {
                        PostRow(post: item)
                    }
                }
            } footer: {
                if app.relayConnectedCount == 0 {
                    Text("No relays connected. Configure and connect to load posts.")
                }
            }
        }
        .listStyle(.insetGrouped)
        .inlineNavigationTitle("Feed")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if isLoading { ProgressView() }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await load() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(isLoading)
            }
        }
        .task { if posts.isEmpty { await load() } }
        .refreshable { await load() }
    }

    private func load() async {
        guard let rt = app.radroots.runtime else { return }
        await MainActor.run {
            isLoading = true
            errorMessage = nil
        }
        do {
            let fetched = try rt.nostrFetchTextNotes(limit: 50, sinceUnix: nil)
            let sorted = fetched.sorted { $0.publishedAt > $1.publishedAt }
            await MainActor.run {
                posts = sorted
                isLoading = false
            }
        } catch {
            await MainActor.run {
                errorMessage = String(describing: error)
                isLoading = false
            }
        }
    }
}

private struct PostRow: View {
    let post: NostrPostEventMetadata

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(post.post.content)
                .font(.body)
                .multilineTextAlignment(.leading)
            HStack(spacing: 8) {
                Text(shortAuthor)
                    .font(.footnote.monospaced())
                    .foregroundStyle(.secondary)
                Text("·")
                    .foregroundStyle(.secondary)
                Text(dateText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private var dateText: String {
        let d = Date(timeIntervalSince1970: TimeInterval(post.publishedAt))
        return d.formatted(date: .abbreviated, time: .shortened)
    }

    private var shortAuthor: String {
        let s = post.author
        let n = s.count
        if n <= 12 { return s }
        let prefix = s.prefix(6)
        let suffix = s.suffix(6)
        return "\(prefix)…\(suffix)"
    }
}
