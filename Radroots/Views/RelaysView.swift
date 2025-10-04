import SwiftUI
import RadrootsKit

struct RelaysView: View {
    @EnvironmentObject private var app: AppState

    private var configuredRelays: [String] {
        (try? RelaySettings.relays()) ?? []
    }

    var body: some View {
        List {
            Section("Relays") {
                RelayMetricRow(label: "Connected", systemImage: "dot.radiowaves.left.and.right", value: app.relayConnectedCount)
                RelayMetricRow(label: "Connecting", systemImage: "antenna.radiowaves.left.and.right", value: app.relayConnectingCount)
                if let last = app.relayLastError {
                    Text(last)
                        .foregroundStyle(.red)
                        .font(.footnote)
                }
            }

            Section("Configured Relays") {
                if configuredRelays.isEmpty {
                    Text("No relays configured")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(configuredRelays, id: \.self) { url in
                        Text(url)
                            .font(.callout.monospaced())
                    }
                }
            }
        }
        .inlineNavigationTitle("Relays")
    }
}

private struct RelayMetricRow: View {
    let label: String
    let systemImage: String
    let value: UInt32

    var body: some View {
        HStack {
            Label(label, systemImage: systemImage)
            Spacer()
            Text("\(value)")
        }
    }
}
