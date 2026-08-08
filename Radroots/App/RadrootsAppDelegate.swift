import UIKit

public final class RadrootsAppDelegate: NSObject, UIApplicationDelegate {
    override public init() {
        super.init()
    }

    public func application(
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

    public func applicationWillTerminate(_: UIApplication) {
        Task {
            await RadrootsLifecycleBridge.shared.requestShutdown()
        }
    }
}
