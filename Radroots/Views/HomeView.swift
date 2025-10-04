import SwiftUI
import RadrootsKit

private enum HomeTab: Hashable {
    case home
    case settings
}

struct HomeView: View {
    @State private var selection: HomeTab = .home

    var body: some View {
        TabView(selection: $selection) {
            NavigationStack {
                HomeDashboardView()
            }
            .tabItem { Label("Home", systemImage: "house.fill") }
            .tag(HomeTab.home)

            NavigationStack {
                SettingsView()
            }
            .tabItem { Label("Settings", systemImage: "gearshape.fill") }
            .tag(HomeTab.settings)
        }
    }
}

private struct HomeDashboardView: View {
    @EnvironmentObject private var app: AppState

    var body: some View {
        List {
            Section("Your Identity") {
                NavigationLink {
                    ProfileView()
                } label: {
                    HStack {
                        Text("Profile")
                        Spacer()
                        Text(app.npub ?? "—")
                            .font(.callout.monospaced())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
            }

            Section("Relays") {
                NavigationLink {
                    RelaysView()
                } label: {
                    HStack {
                        Text("Relays")
                        Spacer()
                        if app.relayConnectedCount > 0 {
                            Label("\(app.relayConnectedCount)", systemImage: "dot.radiowaves.left.and.right")
                                .labelStyle(.titleAndIcon)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .inlineNavigationTitle("Home")
    }
}
