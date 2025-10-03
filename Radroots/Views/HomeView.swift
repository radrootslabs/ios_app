import SwiftUI
import RadrootsKit

struct HomeView: View {
    @EnvironmentObject private var app: AppState

    var body: some View {
        List {
            Section("Your Identity") {
                HStack {
                    Text("npub")
                    Spacer()
                    Text(app.npub ?? "—")
                        .font(.callout.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            Section("Relays") {
                HStack {
                    Label("Connected", systemImage: "dot.radiowaves.left.and.right")
                    Spacer()
                    Text("\(app.relayConnectedCount)")
                }
                HStack {
                    Label("Connecting", systemImage: "antenna.radiowaves.left.and.right")
                    Spacer()
                    Text("\(app.relayConnectingCount)")
                }
                if let last = app.relayLastError {
                    Text(last)
                        .foregroundStyle(.red)
                        .font(.footnote)
                }
            }
        }
        .listStyle(.insetGrouped)
    }
}
