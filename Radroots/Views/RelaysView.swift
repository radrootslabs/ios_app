import SwiftUI

struct RelaysView: View {
    @EnvironmentObject private var app: AppState

    private var configuredRelays: [String] {
        (try? RelaySettings.relays()) ?? []
    }

    var body: some View {
        List {
            Section("Relays") {
                RelayMetricRow(
                    label: "Connected",
                    systemImage: "dot.radiowaves.left.and.right",
                    value: app.relayConnectedCount,
                    accessibilityID: "field_ios.relays.connected_count"
                )
                RelayMetricRow(
                    label: "Connecting",
                    systemImage: "antenna.radiowaves.left.and.right",
                    value: app.relayConnectingCount,
                    accessibilityID: "field_ios.relays.connecting_count"
                )
                if let last = app.relayLastError {
                    Text(last)
                        .foregroundStyle(.red)
                        .font(.footnote)
                        .accessibilityIdentifier("field_ios.relays.last_error")
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
                            .accessibilityIdentifier("field_ios.relays.configured_url")
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .inlineNavigationTitle("Relays")
        .accessibilityIdentifier("field_ios.relays")
    }
}

private struct RelayMetricRow: View {
    let label: String
    let systemImage: String
    let value: UInt32
    let accessibilityID: String

    var body: some View {
        HStack {
            Label(label, systemImage: systemImage)
            Spacer()
            Text("\(value)")
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue("\(value)")
        .accessibilityIdentifier(accessibilityID)
    }
}
