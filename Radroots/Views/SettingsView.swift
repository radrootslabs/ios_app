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
            }

            if app.hasKey {
                Section {
                    Button {
                        exportSecretHex()
                    } label: {
                        Label("Export Secret Hex (Danger)", systemImage: "square.and.arrow.up")
                    }
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
    }

    private func exportSecretHex() {
        guard let rt = radroots.runtime else { return }
        exportError = nil
        do {
            let hex = try rt.keysExportSecretHex()
            UIPasteboard.general.string = hex
        } catch {
            exportError = String(describing: error)
        }
    }
}
