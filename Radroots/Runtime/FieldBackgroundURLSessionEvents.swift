import Foundation

actor FieldBackgroundURLSessionEvents {
    static let shared = FieldBackgroundURLSessionEvents()

    private var backgroundExecution: FieldBackgroundExecution?
    private var pendingEvents: [FieldPendingBackgroundURLSessionEvent]
    private var completesImmediately: Bool

    private init() {
        self.pendingEvents = []
        self.completesImmediately = false
    }

    func attach(_ backgroundExecution: FieldBackgroundExecution) async {
        self.backgroundExecution = backgroundExecution
        completesImmediately = false
        let events = pendingEvents
        pendingEvents = []
        for event in events {
            await backgroundExecution.handleEventsForBackgroundURLSession(
                identifier: event.identifier,
                completionHandler: event.completionHandler
            )
        }
    }

    func handleEvents(
        identifier: String,
        completionHandler: @escaping @Sendable () -> Void
    ) async {
        guard !completesImmediately else {
            completionHandler()
            return
        }
        guard let backgroundExecution else {
            pendingEvents.append(
                FieldPendingBackgroundURLSessionEvent(
                    identifier: identifier,
                    completionHandler: completionHandler
                )
            )
            return
        }
        await backgroundExecution.handleEventsForBackgroundURLSession(
            identifier: identifier,
            completionHandler: completionHandler
        )
    }

    func completePendingAfterStartupFailure() {
        backgroundExecution = nil
        completesImmediately = true
        let events = pendingEvents
        pendingEvents = []
        for event in events {
            event.completionHandler()
        }
    }
}

private struct FieldPendingBackgroundURLSessionEvent: Sendable {
    let identifier: String
    let completionHandler: @Sendable () -> Void
}
