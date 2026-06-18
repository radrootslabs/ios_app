import Foundation

actor FieldBackgroundURLSessionEvents {
    static let shared = FieldBackgroundURLSessionEvents()

    private var backgroundExecution: FieldBackgroundExecution?
    private var pendingEvents: [FieldPendingBackgroundURLSessionEvent]

    private init() {
        self.pendingEvents = []
    }

    func attach(_ backgroundExecution: FieldBackgroundExecution) async {
        self.backgroundExecution = backgroundExecution
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
}

private struct FieldPendingBackgroundURLSessionEvent: Sendable {
    let identifier: String
    let completionHandler: @Sendable () -> Void
}
