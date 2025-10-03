import SwiftUI
import RadrootsKit

@main
struct MyApp: App {
    var body: some Scene {
        WindowGroup {
            RadrootsProvider {
                RootView() 
            }
        }
    }
}
