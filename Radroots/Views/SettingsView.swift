import RadrootsKit
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
                IdentityStateRow(
                    title: "Saved identity",
                    value: app.storedIdentityAvailable ? "Available" : "Missing",
                    identifier: "field_ios.settings.saved_identity"
                )
                IdentityStateRow(
                    title: "Runtime identity",
                    value: app.runtimeIdentityReady ? "Unlocked" : "Locked",
                    identifier: "field_ios.settings.runtime_identity"
                )

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
                    Label("Lock Identity", systemImage: "lock.fill")
                }
                .accessibilityIdentifier("field_ios.settings.sign_out")

                Button(role: .destructive) {
                    showResetConfirmation = true
                } label: {
                    Label("Delete Identity", systemImage: "trash")
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
            "Delete saved Nostr identity?",
            isPresented: $showResetConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete Identity", role: .destructive) {
                resetIdentity()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the identity saved on this iPhone. Lock keeps it available.")
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

private struct IdentityStateRow: View {
    let title: String
    let value: String
    let identifier: String

    var body: some View {
        LabeledContent(title, value: value)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(title)
            .accessibilityValue(value)
            .accessibilityIdentifier(identifier)
    }
}

private struct RuntimeDiagnosticsView: View {
    @EnvironmentObject private var app: AppState
    @State private var preparedExport: RadrootsPreparedExportDocument?
    @State private var activeExport: RadrootsPreparedExportDocument?
    @State private var exportMessage: String?
    @State private var exportError: String?

    var body: some View {
        List {
            Section("Export") {
                Button {
                    prepareExport()
                } label: {
                    Label("Export Diagnostics", systemImage: "square.and.arrow.up")
                }
                .accessibilityIdentifier("field_ios.diagnostics.export")

                if let exportMessage {
                    Text(exportMessage)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("field_ios.diagnostics.export_status")
                }
                if let exportError {
                    Text(exportError)
                        .foregroundStyle(.red)
                        .font(.footnote)
                        .accessibilityIdentifier("field_ios.diagnostics.export_error")
                }
            }

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
        .radrootsDocumentExporter(preparedExport: $preparedExport) { result in
            handleExportCompletion(result)
        }
        .accessibilityIdentifier("field_ios.diagnostics")
    }

    private func prepareExport() {
        exportMessage = nil
        exportError = nil
        do {
            let export = try app.prepareDiagnosticsDocumentExport()
            activeExport = export
            preparedExport = export
        } catch {
            exportError = error.localizedDescription
        }
    }

    private func handleExportCompletion(_ result: Result<RadrootsExportDocumentResult, Error>) {
        if let activeExport {
            app.releasePreparedDocumentExport(activeExport)
        }
        activeExport = nil
        switch result {
        case .success(let exportResult):
            exportMessage = "Exported \(exportResult.exportedFilename)"
            exportError = nil
        case .failure(let error):
            exportError = error.localizedDescription
        }
    }
}
