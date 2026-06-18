import Foundation
import RadrootsKit
import RadrootsKitTesting

struct FieldBackgroundTaskIdentifiers: Equatable, Sendable {
    let refresh: RadrootsBackgroundTaskIdentifier
    let processing: RadrootsBackgroundTaskIdentifier
    let transferSessionIdentifier: String

    init(bundleIdentifier: String) throws {
        let normalized = try FieldBackgroundTaskIdentifiers.normalizedBundleIdentifier(bundleIdentifier)
        self.refresh = try RadrootsBackgroundTaskIdentifier("\(normalized).background.refresh")
        self.processing = try RadrootsBackgroundTaskIdentifier("\(normalized).background.processing")
        self.transferSessionIdentifier = try RadrootsBackgroundTransferValidation.normalizedIdentifier(
            "\(normalized).background.transfer"
        )
    }

    private static func normalizedBundleIdentifier(_ value: String) throws -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else {
            throw FieldLocalStateError.missingBundleIdentifier
        }
        return trimmed
    }
}

struct FieldBackgroundExecutionHandlers: Sendable {
    let refresh: @Sendable () async -> Bool
    let processing: @Sendable () async -> Bool
}

actor FieldBackgroundExecution {
    private let identifiers: FieldBackgroundTaskIdentifiers
    private let scheduler: any RadrootsBackgroundTaskScheduler
    private let transfer: any RadrootsBackgroundTransfer
    private let telemetry: FieldTelemetry
    private let now: @Sendable () -> Date
    private let registerHandlers: @Sendable (FieldBackgroundExecutionHandlers) async throws -> Void
    private var hasRegisteredHandlers = false

    init(
        identifiers: FieldBackgroundTaskIdentifiers,
        scheduler: any RadrootsBackgroundTaskScheduler,
        transfer: any RadrootsBackgroundTransfer,
        telemetry: FieldTelemetry,
        now: @escaping @Sendable () -> Date = Date.init,
        registerHandlers: @escaping @Sendable (FieldBackgroundExecutionHandlers) async throws -> Void
    ) {
        self.identifiers = identifiers
        self.scheduler = scheduler
        self.transfer = transfer
        self.telemetry = telemetry
        self.now = now
        self.registerHandlers = registerHandlers
    }

    static func configured(
        bundleIdentifier: String,
        telemetry: FieldTelemetry
    ) throws -> FieldBackgroundExecution {
        let identifiers = try FieldBackgroundTaskIdentifiers(bundleIdentifier: bundleIdentifier)
        if uiTestWasRequested {
            let scheduler = RadrootsFakeBackgroundTaskScheduler()
            let transfer = RadrootsFakeBackgroundTransfer()
            return FieldBackgroundExecution(
                identifiers: identifiers,
                scheduler: scheduler,
                transfer: transfer,
                telemetry: telemetry,
                registerHandlers: { _ in }
            )
        }
        let scheduler = RadrootsAppleBackgroundTaskScheduler()
        let roots = try FieldLocalState.roots(bundleIdentifier: bundleIdentifier)
        let transfer = try RadrootsAppleBackgroundTransfer(
            roots: roots,
            sessionIdentifier: identifiers.transferSessionIdentifier
        )
        return FieldBackgroundExecution(
            identifiers: identifiers,
            scheduler: scheduler,
            transfer: transfer,
            telemetry: telemetry,
            registerHandlers: { handlers in
                _ = try await scheduler.register(
                    RadrootsAppleBackgroundTaskRegistration(
                        identifier: identifiers.refresh,
                        kind: .appRefresh,
                        handler: handlers.refresh
                    )
                )
                _ = try await scheduler.register(
                    RadrootsAppleBackgroundTaskRegistration(
                        identifier: identifiers.processing,
                        kind: .processing,
                        handler: handlers.processing
                    )
                )
            }
        )
    }

    func start() async throws {
        if !hasRegisteredHandlers {
            try await registerHandlers(
                FieldBackgroundExecutionHandlers(
                    refresh: { true },
                    processing: { true }
                )
            )
            hasRegisteredHandlers = true
            telemetry.backgroundExecution(operation: "register", outcome: "success", taskCount: 2)
        }
        _ = try await schedulePermittedTasks(reason: "startup")
    }

    @discardableResult
    func schedulePermittedTasks(reason: String) async throws -> [RadrootsBackgroundTaskSnapshot] {
        let refresh = try RadrootsBackgroundTaskRequest(
            identifier: identifiers.refresh,
            kind: .appRefresh,
            earliestBeginDate: now().addingTimeInterval(15 * 60)
        )
        let processing = try RadrootsBackgroundTaskRequest(
            identifier: identifiers.processing,
            kind: .processing,
            earliestBeginDate: now().addingTimeInterval(60 * 60)
        )
        let snapshots = [
            try await scheduler.submit(refresh),
            try await scheduler.submit(processing)
        ]
        telemetry.backgroundExecution(operation: "schedule", outcome: "success", taskCount: snapshots.count, reason: reason)
        return snapshots
    }

    func cancelAll() async {
        do {
            try await scheduler.cancelAll()
            telemetry.backgroundExecution(operation: "cancel_all", outcome: "success")
        } catch {
            telemetry.backgroundExecution(operation: "cancel_all", outcome: FieldTelemetry.backgroundExecutionOutcome(for: error))
        }
    }

    func pendingTaskSnapshots() async -> [RadrootsBackgroundTaskSnapshot] {
        do {
            return try await scheduler.pendingTasks()
        } catch {
            telemetry.backgroundExecution(operation: "pending_tasks", outcome: FieldTelemetry.backgroundExecutionOutcome(for: error))
            return []
        }
    }

    func transferSnapshots() async -> [RadrootsBackgroundTransferSnapshot] {
        do {
            return try await transfer.snapshots()
        } catch {
            telemetry.backgroundExecution(operation: "transfer_snapshots", outcome: FieldTelemetry.backgroundExecutionOutcome(for: error))
            return []
        }
    }

    private static var uiTestWasRequested: Bool {
        let environment = ProcessInfo.processInfo.environment
        let arguments = ProcessInfo.processInfo.arguments
        return environment["RADROOTS_FIELD_IOS_UI_TEST"] == "true" ||
            arguments.contains("--radroots-field-ios-ui-test")
    }
}
