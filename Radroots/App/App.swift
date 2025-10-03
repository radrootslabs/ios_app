import SwiftUI
import RadrootsKit

@main
struct RadrootsApp: App {
    var body: some Scene {
        WindowGroup {
            RadrootsProvider {
                AppRootView()
            }
        }
    }
}
