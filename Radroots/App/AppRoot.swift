import SwiftUI
import RadrootsKit

struct AppRootView: View {
    @EnvironmentObject private var app: AppState
    @State private var selectedTab: MainTab = .home

    var body: some View {
        MainTabs(selection: $selectedTab)
            .fullScreenCover(
                isPresented: Binding(
                    get: { app.hasKey == false },
                    set: { _ in }
                )
            ) {
                SetupView {
                    app.refresh()
                }
                .interactiveDismissDisabled(true)
            }
    }
}

enum MainTab: Hashable {
    case home
    case settings
}

private struct MainTabs: View {
    @EnvironmentObject private var app: AppState
    @Binding var selection: MainTab

    var body: some View {
        TabView(selection: $selection) {
            RequiresKey {
                NavigationStack {
                    HomeView()
                        .navigationTitle("Home")
                }
            }
            .tabItem { Label("Home", systemImage: "house.fill") }
            .tag(MainTab.home)

            NavigationStack {
                SettingsView()
                    .navigationTitle("Settings")
            }
            .tabItem { Label("Settings", systemImage: "gearshape.fill") }
            .tag(MainTab.settings)
        }
    }
}

private struct RequiresKey<Content: View>: View {
    @EnvironmentObject private var app: AppState
    @ViewBuilder var content: () -> Content

    var body: some View {
        if app.hasKey {
            content()
        } else {
            LockedView()
        }
    }
}

private struct LockedView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "lock.fill")
                .font(.system(size: 44, weight: .semibold))
            Text("Locked")
                .font(.title2.weight(.semibold))
            Text("Create or import a Nostr key to continue.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .padding()
    }
}
