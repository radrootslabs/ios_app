import UIKit

final class RadrootsAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _: UIApplication,
        handleEventsForBackgroundURLSession identifier: String,
        completionHandler: @escaping () -> Void
    ) {
        let completion = RadrootsCompletionOnce(completionHandler)
        Task {
            await RadrootsBackgroundEventRouter.shared.handle(
                identifier: identifier,
                completion: completion
            )
        }
    }

    func applicationWillTerminate(_: UIApplication) {
        Task {
            await RadrootsLifecycleBridge.shared.requestShutdown()
        }
    }
}
