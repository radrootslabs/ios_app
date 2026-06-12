import SwiftUI

@main
struct RadrootsApp: App {
    var body: some Scene {
        WindowGroup {
            RadrootsProvider {
                AppEntry {
                    HomeView()
                }
            }
        }
    }
}
