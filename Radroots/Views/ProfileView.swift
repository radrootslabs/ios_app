import SwiftUI
import RadrootsKit

public struct ProfileView: View {
    @EnvironmentObject private var app: AppState

    @State private var name: String = ""
    @State private var displayName: String = ""
    @State private var nip05: String = ""
    @State private var about: String = ""

    @State private var original: OriginalProfile = .empty
    @State private var isLoading: Bool = false
    @State private var isPosting: Bool = false
    @State private var postMessage: String?
    @State private var showMessage: Bool = false
    @FocusState private var focusedField: Field?

    enum Field: Hashable { case name, displayName, nip05, about }

    public init() {}

    public var body: some View {
        Form {
            Section(header: Text("Profile")) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("name").font(.footnote).foregroundStyle(.secondary)
                    TextField("name", text: $name)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.next)
                        .focused($focusedField, equals: .name)
                        .onSubmit { focusedField = .displayName }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("display_name").font(.footnote).foregroundStyle(.secondary)
                    TextField("display name", text: $displayName)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                        .submitLabel(.next)
                        .focused($focusedField, equals: .displayName)
                        .onSubmit { focusedField = .nip05 }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("nip05").font(.footnote).foregroundStyle(.secondary)
                    TextField("user@example.com", text: $nip05)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.next)
                        .focused($focusedField, equals: .nip05)
                        .onSubmit { focusedField = .about }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("about").font(.footnote).foregroundStyle(.secondary)
                    TextEditor(text: $about)
                        .frame(minHeight: 120)
                        .focused($focusedField, equals: .about)
                }
            }

            Section {
                SectionWideButton("Post Kind 0", enabled: isPostEnabled, isProminent: hasChanges) {
                    post()
                }
                .animation(.easeInOut(duration: 0.15), value: hasChanges)
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    if !isConnected {
                        Text("No relays connected. Connect to at least one relay to post.")
                    }
                    if let msg = postMessage {
                        Text(msg)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollDismissesKeyboard(.interactively)
        .inlineNavigationTitle("Profile")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if isLoading || isPosting { ProgressView() }
            }
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { focusedField = nil }
            }
        }
        .onAppear { loadProfile() }
        .refreshable { loadProfile() }
        .alert("Post Result", isPresented: $showMessage) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(postMessage ?? "")
        }
    }

    private var isConnected: Bool { app.relayConnectedCount > 0 }
    private var isPostEnabled: Bool { isConnected && !isPosting }
    private var hasChanges: Bool {
        name != original.name ||
        displayName != original.displayName ||
        nip05 != original.nip05 ||
        about != original.about
    }

    private func loadProfile() {
        guard let rt = app.radroots.runtime else { return }
        isLoading = true
        Task {
            let prof = rt.nostrProfileForSelf()
            await MainActor.run {
                self.original = OriginalProfile.from(prof)
                self.name = original.name
                self.displayName = original.displayName
                self.nip05 = original.nip05
                self.about = original.about
                self.isLoading = false
            }
        }
    }

    private func post() {
        guard let rt = app.radroots.runtime, isPostEnabled else { return }
        isPosting = true
        postMessage = nil
        let payload = PostPayload(name: name, displayName: displayName, nip05: nip05, about: about)
        Task {
            do {
                let id = try rt.nostrPostProfile(
                    name: payload.name,
                    displayName: payload.displayName,
                    nip05: payload.nip05,
                    about: payload.about
                )
                await MainActor.run {
                    self.original = OriginalProfile(name: name, displayName: displayName, nip05: nip05, about: about)
                    self.isPosting = false
                    self.postMessage = "Posted kind:0 event: \(id)"
                    self.showMessage = true
                    self.app.refresh()
                }
            } catch {
                await MainActor.run {
                    self.isPosting = false
                    self.postMessage = "Failed to post profile: \(error)"
                    self.showMessage = true
                }
            }
        }
    }
}

private struct OriginalProfile: Equatable {
    var name: String
    var displayName: String
    var nip05: String
    var about: String

    static let empty = OriginalProfile(name: "", displayName: "", nip05: "", about: "")

    static func from(_ p: NostrProfile?) -> OriginalProfile {
        OriginalProfile(
            name: p?.name ?? "",
            displayName: p?.displayName ?? "",
            nip05: p?.nip05 ?? "",
            about: p?.about ?? ""
        )
    }
}

private struct PostPayload {
    var name: String
    var displayName: String
    var nip05: String
    var about: String
}
