import SwiftUI

private enum HomeTab: Hashable {
    case feed
    case market
    case settings
}

struct HomeView: View {
    @State private var selection: HomeTab = .feed

    var body: some View {
        TabView(selection: $selection) {
            NavigationStack {
                PostFeedView()
            }
            .tabItem { Label("Feed", systemImage: "text.bubble.fill") }
            .tag(HomeTab.feed)

            NavigationStack {
                MarketView()
            }
            .tabItem { Label("Market", systemImage: "leaf") }
            .tag(HomeTab.market)

            NavigationStack {
                SettingsView()
            }
            .tabItem { Label("Settings", systemImage: "gearshape.fill") }
            .tag(HomeTab.settings)
        }
    }
}
