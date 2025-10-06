import SwiftUI
import RadrootsKit

struct PostFeedView: View {
    @EnvironmentObject private var app: AppState
    @State private var posts: [NostrPostEventMetadata] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var expandedReplyFor: String?
    @State private var draftReplies: [String: String] = [:]
    @State private var sendingReplyFor: Set<String> = []
    @State private var resultTitle: String = ""
    @State private var resultMessage: String = ""
    @State private var showResult: Bool = false

    var body: some View {
        List {
            if let e = errorMessage {
                Section {
                    Text(e)
                        .foregroundStyle(.red)
                        .font(.footnote)
                }
            }

            Section {
                ForEach(posts, id: \.id) { item in
                    FeedPostRow(
                        post: item,
                        isExpanded: expandedReplyFor == item.id,
                        onToggleReply: { toggleReply(for: item.id) }
                    )
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))

                    if expandedReplyFor == item.id {
                        InlineReplyComposer(
                            text: bindingForReply(item.id),
                            isSending: sendingReplyFor.contains(item.id),
                            onCancel: { expandedReplyFor = nil },
                            onSend: { handleReply(item) }
                        )
                        .listRowInsets(EdgeInsets(top: 6, leading: 64, bottom: 12, trailing: 16))
                        .listRowSeparator(.hidden)
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
                Button { Task { await load() } } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(isLoading)
            }
        }
        .task { if posts.isEmpty { await load() } }
        .refreshable { await load() }
        .alert(resultTitle, isPresented: $showResult) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(resultMessage)
        }
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
            DebugDump.posts(sorted, label: "PostFeed.kind1.displayed")
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

    private func toggleReply(for id: String) {
        expandedReplyFor = expandedReplyFor == id ? nil : id
    }

    private func bindingForReply(_ id: String) -> Binding<String> {
        Binding<String>(
            get: { draftReplies[id, default: ""] },
            set: { draftReplies[id] = $0 }
        )
    }

    private func handleReply(_ post: NostrPostEventMetadata) {
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
                await MainActor.run {
                    draftReplies[post.id] = ""
                    expandedReplyFor = nil
                    sendingReplyFor.remove(post.id)
                    resultTitle = "Reply Posted"
                    resultMessage = "Event \(id)"
                    showResult = true
                    app.refresh()
                }
            } catch {
                await MainActor.run {
                    sendingReplyFor.remove(post.id)
                    resultTitle = "Failed to Post Reply"
                    resultMessage = String(describing: error)
                    showResult = true
                }
            }
        }
    }
}

fileprivate struct FeedPostRow: View {
    let post: NostrPostEventMetadata
    let isExpanded: Bool
    let onToggleReply: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            AvatarView(seed: post.author)
                .frame(width: 40, height: 40)
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(shortAuthor(post.author))
                        .font(.callout.monospaced())
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text("·")
                        .foregroundStyle(.secondary)
                    Text(relativeTime(post.publishedAt))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Text(post.post.content)
                    .font(.body)
                    .multilineTextAlignment(.leading)
                HStack(spacing: 24) {
                    Button(action: onToggleReply) {
                        HStack(spacing: 6) {
                            Image(systemName: isExpanded ? "bubble.left.fill" : "bubble.left")
                            Text("Reply")
                        }
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
                .font(.subheadline.weight(.semibold))
                .padding(.top, 2)
            }
        }
        .padding(.vertical, 4)
    }

    private func relativeTime(_ unix: UInt64) -> String {
        let d = Date(timeIntervalSince1970: TimeInterval(unix))
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f.localizedString(for: d, relativeTo: Date())
    }

    private func shortAuthor(_ s: String) -> String {
        let n = s.count
        if n <= 12 { return s }
        let prefix = s.prefix(6)
        let suffix = s.suffix(6)
        return "\(prefix)…\(suffix)"
    }
}

fileprivate struct InlineReplyComposer: View {
    @Binding var text: String
    let isSending: Bool
    let onCancel: () -> Void
    let onSend: () -> Void
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack(alignment: .topLeading) {
                TextEditor(text: $text)
                    .font(.body)
                    .padding(10)
                    .frame(minHeight: 160, maxHeight: 220, alignment: .topLeading)
                    .scrollContentBackground(.hidden)
                    .background(Color.secondary.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .focused($focused)

                if text.isEmpty {
                    Text("Write a reply")
                        .foregroundStyle(.secondary)
                        .padding(.top, 16)
                        .padding(.leading, 16)
                        .allowsHitTesting(false)
                }
            }

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { onCancel() }
                    .buttonStyle(.bordered)
                Button {
                    onSend()
                } label: {
                    if isSending {
                        ProgressView()
                    } else {
                        Text("Send").fontWeight(.semibold)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSending)
            }
        }
        .onAppear { focused = true }
    }
}

fileprivate struct AvatarView: View {
    let seed: String

    var body: some View {
        ZStack {
            Circle().fill(gradient)
            Text(initials)
                .font(.caption.weight(.bold))
                .foregroundStyle(.white.opacity(0.9))
        }
        .accessibilityHidden(true)
    }

    private var initials: String {
        let trimmed = seed.replacingOccurrences(of: "npub1", with: "")
        return trimmed.first.map { String($0).uppercased() } ?? "?"
    }

    private var gradient: LinearGradient {
        let hash = abs(seed.hashValue)
        let hue = Double(hash % 360) / 360.0
        let c1 = Color(hue: hue, saturation: 0.65, brightness: 0.85)
        let c2 = Color(hue: (hue + 0.08).truncatingRemainder(dividingBy: 1),
                       saturation: 0.55,
                       brightness: 0.75)
        return LinearGradient(
            gradient: Gradient(colors: [c1, c2]),
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}
