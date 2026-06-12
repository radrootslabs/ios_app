import SwiftUI
import RadrootsKit

struct SettingsView: View {
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var radroots: Radroots
    @State private var exportError: String?

    var body: some View {
        List {
            Section("Account") {
                if let npub = app.npub {
                    CopyRow(title: "npub", value: npub)
                } else {
                    Text("No key configured")
                        .foregroundStyle(.secondary)
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

            Section("Trade") {
                if let rhi = TradeSettings.rhiPubkeyOptional {
                    CopyRow(title: "RHI Pubkey", value: rhi)
                } else {
                    Text("Listing publish and fetch use the shared field runtime.")
                        .foregroundStyle(.secondary)
                }
            }

            if app.hasKey {
                Section {
                    Button {
                        exportSecretHex()
                    } label: {
                        Label("Export Secret Hex (Danger)", systemImage: "square.and.arrow.up")
                    }
                } header: {
                    Text("Security")
                } footer: {
                    if let exportError {
                        Text(exportError).foregroundStyle(.red)
                    } else {
                        Text("Keep your secret key safe. Anyone with it controls your identity.")
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .inlineNavigationTitle("Settings")
        .accessibilityIdentifier("field_ios.settings")
    }

    private func exportSecretHex() {
        guard let rt = radroots.runtime else { return }
        exportError = nil
        do {
            guard let hex = try rt.accountsExportSelectedSecretHex() else {
                exportError = "No selected account has an exportable secret."
                return
            }
            UIPasteboard.general.string = hex
        } catch {
            exportError = String(describing: error)
        }
    }
}
