import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var app: AppState
    @State private var showResetConfirmation = false
    @State private var resetError: String?

    var body: some View {
        List {
            Section("Identity") {
                Text(app.identityDisplayName)
                    .font(.headline)
                if let npub = app.npub {
                    CopyRow(title: "npub", value: npub)
                } else {
                    Text("No local Nostr identity is selected.")
                        .foregroundStyle(.secondary)
                }
                LabeledContent("Stored identities", value: app.storedIdentityAvailable ? "1" : "0")
                LabeledContent("Runtime identity", value: app.runtimeIdentityReady ? "Ready" : "Locked")

                NavigationLink {
                    ProfileView()
                } label: {
                    Label("Profile", systemImage: "person.crop.circle")
                }
            }

            Section("Network") {
                NavigationLink {
                    RelaysView()
                } label: {
                    Label("Relays", systemImage: "dot.radiowaves.left.and.right")
                }
            }

            if diagnosticsAvailable {
                Section("Operator") {
                    NavigationLink {
                        RuntimeDiagnosticsView()
                    } label: {
                        Label("Diagnostics", systemImage: "stethoscope")
                    }
                    .accessibilityIdentifier("field_ios.settings.diagnostics")
                }
            }

            Section("Trade") {
                if let rhi = TradeSettings.rhiPubkeyOptional {
                    CopyRow(title: "RHI Pubkey", value: rhi)
                } else {
                    Text("Listing publish and fetch use the shared field runtime.")
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                Button {
                    app.signOut()
                } label: {
                    Label("Sign Out", systemImage: "lock.fill")
                }
                .accessibilityIdentifier("field_ios.settings.sign_out")

                Button(role: .destructive) {
                    showResetConfirmation = true
                } label: {
                    Label("Reset Local Identity", systemImage: "trash")
                }
                .accessibilityIdentifier("field_ios.settings.reset_identity")
            } footer: {
                if let resetError {
                    Text(resetError)
                        .foregroundStyle(.red)
                }
            }
        }
        .listStyle(.insetGrouped)
        .inlineNavigationTitle("Settings")
        .confirmationDialog(
            "Reset local Nostr identity?",
            isPresented: $showResetConfirmation,
            titleVisibility: .visible
        ) {
            Button("Reset Identity", role: .destructive) {
                resetIdentity()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the local identity from this app. Sign out keeps it.")
        }
        .accessibilityIdentifier("field_ios.settings")
    }

    private var diagnosticsAvailable: Bool {
        BuildConfig.string(.runtimeMode) != "production"
    }

    private func resetIdentity() {
        resetError = nil
        Task {
            do {
                try await app.resetLocalIdentity()
            } catch {
                resetError = error.localizedDescription
            }
        }
    }
}

private struct RuntimeDiagnosticsView: View {
    @EnvironmentObject private var app: AppState

    var body: some View {
        List {
            Section("Relay") {
                LabeledContent("Connected", value: "\(app.relayConnectedCount)")
                LabeledContent("Connecting", value: "\(app.relayConnectingCount)")
                if let relayLastError = app.relayLastError {
                    Text(relayLastError)
                        .foregroundStyle(.red)
                        .font(.footnote)
                }
            }

            Section("Runtime Metadata") {
                Text(app.infoJSONString.isEmpty ? "No runtime metadata available." : app.infoJSONString)
                    .font(.footnote.monospaced())
                    .textSelection(.enabled)
            }
        }
        .listStyle(.insetGrouped)
        .inlineNavigationTitle("Diagnostics")
        .accessibilityIdentifier("field_ios.diagnostics")
    }
}
