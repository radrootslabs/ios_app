import SwiftUI
import RadrootsKit

struct SettingsView: View {
    @EnvironmentObject private var app: AppState

    var body: some View {
        Form {
            Section("Runtime Info") {
                TextEditor(text: .constant(app.infoJSONString))
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 200)
                    .disabled(true)
            }

            Section("Keys") {
                if app.hasKey {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Key loaded")
                            .font(.headline)
                        if let npub = app.npub {
                            Text(npub)
                                .textSelection(.enabled)
                                .font(.system(.footnote, design: .monospaced))
                        }
                    }
                } else {
                    Text("No key loaded")
                }
            }

            Section("Relays") {
                HStack(spacing: 8) {
                    Circle()
                        .fill(color(for: app.relayLight))
                        .frame(width: 10, height: 10)
                    Text("Connected \(app.relayConnectedCount) • Connecting \(app.relayConnectingCount)")
                }
                if let err = app.relayLastError {
                    Text(err)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Settings")
        .onAppear { app.refresh() }
    }

    private func color(for light: AppState.RelayLight) -> Color {
        switch light {
        case .green:  return .green
        case .yellow: return .yellow
        case .red:    return .red
        }
    }
}
