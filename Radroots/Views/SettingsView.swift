import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var app: AppState

    var body: some View {
        List {
            Section("Account") {
                if let displayName = app.accountDisplayName {
                    Text(displayName)
                }
                if let username = app.username {
                    CopyRow(title: "Username", value: username)
                }
                if let npub = app.npub {
                    CopyRow(title: "npub", value: npub)
                } else {
                    Text("Nostr identity is prepared after sign-in.")
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

            Section {
                Button(role: .destructive) {
                    app.logout()
                } label: {
                    Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                }
            }
        }
        .listStyle(.insetGrouped)
        .inlineNavigationTitle("Settings")
        .accessibilityIdentifier("field_ios.settings")
    }
}
