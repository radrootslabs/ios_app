import RadrootsKit
import SwiftUI

struct PostDetailView: View {
    @EnvironmentObject private var app: AppState
    let post: NostrPostEventMetadata
    @State private var showCopied = false

    var body: some View {
        List {
            Section("Content") {
                Text(post.post.content)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }

            Section("Event") {
                CopyRow(title: "Author", value: post.author) { showCopied = true }
                CopyRow(title: "Event ID", value: post.id) { showCopied = true }

                LabeledContent("Published") {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(absoluteDate)
                        Text(relativeDate)
                            .foregroundStyle(.secondary)
                            .font(.footnote)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .inlineNavigationTitle("Post")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if let shareRequest = try? app.publicPostShareRequest(content: post.post.content),
                   let shareLink = try? RadrootsSharePresentationLink(request: shareRequest, label: {
                       Image(systemName: "square.and.arrow.up")
                   }) {
                    shareLink
                        .accessibilityIdentifier("field_ios.post.share")
                } else {
                    Button {} label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .disabled(true)
                    .accessibilityIdentifier("field_ios.post.share_unavailable")
                }
            }
        }
        .toast(isPresented: $showCopied) {
            Text("Copied")
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.thinMaterial, in: Capsule())
        }
    }

    private var absoluteDate: String {
        let d = Date(timeIntervalSince1970: TimeInterval(post.publishedAt))
        return d.formatted(date: .abbreviated, time: .shortened)
    }

    private var relativeDate: String {
        let d = Date(timeIntervalSince1970: TimeInterval(post.publishedAt))
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .full
        return f.localizedString(for: d, relativeTo: Date())
    }
}
