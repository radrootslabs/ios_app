import SwiftUI

@main
struct RadrootsApp: App {
    @UIApplicationDelegateAdaptor(RadrootsAppDelegate.self) private var appDelegate

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
