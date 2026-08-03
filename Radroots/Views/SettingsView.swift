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
                    if app.canOpenNostrProfile {
                        Button {
                            Task {
                                await app.openCurrentNostrProfile()
                            }
                        } label: {
                            Label("Open Nostr Profile", systemImage: "person.crop.circle.badge.arrow.forward")
                        }
                        .accessibilityIdentifier("field_ios.settings.open_nostr_profile")
                    } else {
                        Text("No Nostr client is available.")
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("field_ios.settings.nostr_profile_unavailable")
                    }
                    if let status = app.externalActionStatus {
                        Text(status)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("field_ios.external_actions.status")
                    }
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
                if let userPresenceStatus = app.userPresenceStatus {
                    Text(userPresenceStatus)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("field_ios.user_presence.status")
                }

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
                        .accessibilityIdentifier("field_ios.settings.reset_error")
                }
            }
        }
        .listStyle(.insetGrouped)
        .inlineNavigationTitle("Settings")
        .task {
            await app.refreshNostrProfileExternalActionCapability()
        }
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
                resetError = error.fieldRuntimeMessage
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
                LabeledContent("Read operations", value: app.relaySourceAvailable ? "Available" : "Unavailable")
                LabeledContent("Write operations", value: app.relaySinkAvailable ? "Available" : "Unavailable")
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
            exportError = error.fieldRuntimeMessage
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
            exportError = error.fieldRuntimeMessage
        }
    }
}
