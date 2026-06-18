import UIKit

final class RadrootsAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        handleEventsForBackgroundURLSession identifier: String,
        completionHandler: @escaping () -> Void
    ) {
        let completion = FieldBackgroundURLSessionCompletion(completionHandler)
        Task {
            await FieldBackgroundURLSessionEvents.shared.handleEvents(identifier: identifier) {
                completion.complete()
            }
        }
    }
}

private final class FieldBackgroundURLSessionCompletion: @unchecked Sendable {
    private let completionHandler: () -> Void

    init(_ completionHandler: @escaping () -> Void) {
        self.completionHandler = completionHandler
    }

    func complete() {
        completionHandler()
    }
}
