import SwiftUI
import RadrootsKit

struct PostCreateView: View {
    @EnvironmentObject private var app: AppState
    @State private var text: String = ""
    @State private var isPosting = false
    @State private var resultMessage: String?
    @State private var showResult = false
    @FocusState private var focused: Bool

    private var isConnected: Bool { app.relayConnectedCount > 0 }
    private var canPost: Bool {
        isConnected && !isPosting && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        Form {
            Section {
                ZStack(alignment: .topLeading) {
                    TextEditor(text: $text)
                        .frame(minHeight: 160)
                        .focused($focused)
                        .submitLabel(.send)
                    if text.isEmpty {
                        Text("What's happening?")
                            .foregroundStyle(.secondary)
                            .padding(.top, 8)
                            .padding(.leading, 5)
                            .allowsHitTesting(false)
                    }
                }
                HStack {
                    Text("\(text.count)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        post()
                    } label: {
                        if isPosting {
                            ProgressView()
                        } else {
                            Text("Post")
                                .fontWeight(.semibold)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canPost)
                }
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    if !isConnected {
                        Text("No relays connected. Configure and connect to post.")
                            .foregroundStyle(.red)
                    }
                    if let e = app.relayLastError {
                        Text(e).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .inlineNavigationTitle("Compose")
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { focused = false }
            }
        }
        .alert("Post Result", isPresented: $showResult) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(resultMessage ?? "")
        }
        .onAppear { focused = true }
    }

    private func post() {
        guard let rt = app.radroots.runtime else { return }
        let content = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { return }
        isPosting = true
        resultMessage = nil
        Task {
            do {
                let id = try rt.nostrPostTextNote(content: content)
                await MainActor.run {
                    resultMessage = "Posted kind:1 event: \(id)"
                    showResult = true
                    text = ""
                    isPosting = false
                    app.refresh()
                }
            } catch {
                await MainActor.run {
                    resultMessage = "Failed to post: \(error)"
                    showResult = true
                    isPosting = false
                }
            }
        }
    }
}
