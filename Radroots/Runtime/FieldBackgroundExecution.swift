import Foundation
import RadrootsKit

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
    private static let stagedBlobRetention: TimeInterval = 24 * 60 * 60

    private let identifiers: FieldBackgroundTaskIdentifiers
    private let scheduler: any RadrootsBackgroundTaskScheduler
    private let transfer: any RadrootsBackgroundTransfer
    private let roots: RadrootsAppleFileRoots
    private let telemetry: FieldTelemetry
    private let now: @Sendable () -> Date
    private let registerHandlers: @Sendable (FieldBackgroundExecutionHandlers) async throws -> Void
    private var runtimeService: FieldRuntimeService?
    private var identityUnlocked = false
    private var hasRegisteredHandlers = false

    init(
        identifiers: FieldBackgroundTaskIdentifiers,
        scheduler: any RadrootsBackgroundTaskScheduler,
        transfer: any RadrootsBackgroundTransfer,
        roots: RadrootsAppleFileRoots,
        telemetry: FieldTelemetry,
        now: @escaping @Sendable () -> Date = Date.init,
        registerHandlers: @escaping @Sendable (FieldBackgroundExecutionHandlers) async throws -> Void
    ) {
        self.identifiers = identifiers
        self.scheduler = scheduler
        self.transfer = transfer
        self.roots = roots
        self.telemetry = telemetry
        self.now = now
        self.registerHandlers = registerHandlers
    }

    static func configured(
        bundleIdentifier: String,
        telemetry: FieldTelemetry
    ) throws -> FieldBackgroundExecution {
        let identifiers = try FieldBackgroundTaskIdentifiers(bundleIdentifier: bundleIdentifier)
        let roots = try FieldLocalState.roots(bundleIdentifier: bundleIdentifier)
        #if DEBUG
        if FieldUITestHarness.isRequested {
            let scheduler = FieldUITestBackgroundTaskScheduler()
            let transfer = FieldUITestBackgroundTransfer()
            let now: @Sendable () -> Date
            if FieldBackgroundExecutionUITestProbe.isRequested {
                now = { Date.distantFuture }
            } else {
                now = Date.init
            }
            return FieldBackgroundExecution(
                identifiers: identifiers,
                scheduler: scheduler,
                transfer: transfer,
                roots: roots,
                telemetry: telemetry,
                now: now,
                registerHandlers: { _ in }
            )
        }
        #endif
        let scheduler = RadrootsAppleBackgroundTaskScheduler()
        let transfer = try RadrootsAppleBackgroundTransfer(
            roots: roots,
            sessionIdentifier: identifiers.transferSessionIdentifier
        )
        return FieldBackgroundExecution(
            identifiers: identifiers,
            scheduler: scheduler,
            transfer: transfer,
            roots: roots,
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
                    refresh: { [weak self] in
                        await self?.performMaintenance(reason: "refresh_task") ?? false
                    },
                    processing: { [weak self] in
                        await self?.performMaintenance(reason: "processing_task") ?? false
                    }
                )
            )
            hasRegisteredHandlers = true
            telemetry.backgroundExecution(operation: "handler_registration", outcome: "success", taskCount: 2)
        }
        _ = try await schedulePermittedTasks(reason: "startup")
    }

    func updateRuntimeState(service: FieldRuntimeService?, identityUnlocked: Bool) {
        self.runtimeService = service
        self.identityUnlocked = identityUnlocked
    }

    @discardableResult
    func schedulePermittedTasks(reason: String) async throws -> [RadrootsBackgroundTaskSnapshot] {
        do {
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
        } catch {
            telemetry.backgroundExecution(
                operation: "schedule",
                outcome: FieldTelemetry.backgroundExecutionOutcome(for: error),
                reason: reason
            )
            throw error
        }
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

    func handleEventsForBackgroundURLSession(
        identifier: String,
        completionHandler: @escaping @Sendable () -> Void
    ) async {
        await transfer.handleEventsForBackgroundURLSession(
            identifier: identifier,
            completionHandler: completionHandler
        )
        telemetry.backgroundExecution(operation: "background_url_session_events", outcome: "success")
    }

    func uiTestProbeValue() async -> String? {
        guard FieldBackgroundExecutionUITestProbe.isRequested else {
            return nil
        }
        do {
            return try await buildUITestProbeValue()
        } catch {
            return FieldBackgroundExecutionUITestProbe.failureValue(
                outcome: FieldTelemetry.backgroundExecutionOutcome(for: error)
            )
        }
    }

    @discardableResult
    func performMaintenance(reason: String) async -> Bool {
        let transferCount = await inspectTransferSnapshots(reason: reason)
        let sweptCount = sweepExpiredStagedBlobs(reason: reason)
        let relaySucceeded = await refreshRelaysIfAllowed(reason: reason)
        let succeeded = transferCount != nil && sweptCount != nil && relaySucceeded
        telemetry.backgroundExecution(
            operation: "maintenance",
            outcome: succeeded ? "success" : "partial_failure",
            stagedBlobCount: sweptCount,
            transferCount: transferCount,
            identityUnlocked: identityUnlocked,
            reason: reason
        )
        return succeeded
    }

    private func buildUITestProbeValue() async throws -> String {
        let registered = hasRegisteredHandlers
        let scheduledTaskCount = await fakeSubmittedRequestCount()
        let pendingBeforeMaintenance = try await scheduler.pendingTasks().count
        let transferSnapshotCount = try await seedUITestTransferSnapshot()
        let stagedBlobRemoved = try await seedUITestStagedBlobAndRunMaintenance()
        let pendingBeforeCancel = try await scheduler.pendingTasks().count
        await cancelAll()
        let pendingAfterCancel = try await scheduler.pendingTasks().count
        let cancellationObserved = await fakeCancelAllCount() > 0
        try? await Task.sleep(nanoseconds: 100_000_000)
        let events = await telemetry.recordedEventsForUITest()
        return FieldBackgroundExecutionUITestProbe.value(
            registered: registered,
            scheduledTaskCount: scheduledTaskCount,
            pendingBeforeMaintenance: pendingBeforeMaintenance,
            pendingBeforeCancel: pendingBeforeCancel,
            pendingAfterCancel: pendingAfterCancel,
            cancellationObserved: cancellationObserved,
            stagedBlobRemoved: stagedBlobRemoved,
            transferSnapshotCount: transferSnapshotCount,
            events: events
        )
    }

    private func seedUITestTransferSnapshot() async throws -> Int {
        #if DEBUG
        guard let fakeTransfer = transfer as? FieldUITestBackgroundTransfer else {
            return try await transfer.snapshots().count
        }
        let request = try RadrootsBackgroundTransferRequest(
            remoteURL: URL(string: "https://radroots.org/field-ios-background-probe")!,
            method: .get,
            operation: .download(
                destination: .file(
                    RadrootsFileReference(
                        scope: .cache,
                        relativePath: "ui_tests/background_execution/probe-download.bin"
                    )
                )
            ),
            metadata: ["purpose": "background_execution_probe"]
        )
        _ = try await fakeTransfer.enqueue(request)
        return try await fakeTransfer.snapshots().count
        #else
        return try await transfer.snapshots().count
        #endif
    }

    private func seedUITestStagedBlobAndRunMaintenance() async throws -> Bool {
        let fileAccess = RadrootsAppleFileAccess(roots: roots)
        let blob = try fileAccess.stageBlob(
            Data("field-ios-background-probe".utf8),
            mediaType: "text/plain",
            filenameHint: "background-probe.txt"
        )
        _ = await performMaintenance(reason: "ui_test_probe")
        do {
            _ = try fileAccess.readStagedBlob(blob)
            return false
        } catch RadrootsAppleFileError.notFound {
            return true
        } catch {
            throw error
        }
    }

    private func fakeSubmittedRequestCount() async -> Int {
        #if DEBUG
        guard let fakeScheduler = scheduler as? FieldUITestBackgroundTaskScheduler else {
            return (try? await scheduler.pendingTasks().count) ?? 0
        }
        return await fakeScheduler.submittedRequestCount
        #else
        return (try? await scheduler.pendingTasks().count) ?? 0
        #endif
    }

    private func fakeCancelAllCount() async -> Int {
        #if DEBUG
        guard let fakeScheduler = scheduler as? FieldUITestBackgroundTaskScheduler else {
            return 0
        }
        return await fakeScheduler.cancelAllCount
        #else
        return 0
        #endif
    }

    private func inspectTransferSnapshots(reason: String) async -> Int? {
        do {
            let snapshots = try await transfer.snapshots()
            telemetry.backgroundExecution(
                operation: "transfer_inspect",
                outcome: "success",
                transferCount: snapshots.count,
                reason: reason
            )
            return snapshots.count
        } catch {
            telemetry.backgroundExecution(
                operation: "transfer_inspect",
                outcome: FieldTelemetry.backgroundExecutionOutcome(for: error),
                reason: reason
            )
            return nil
        }
    }

    private func sweepExpiredStagedBlobs(reason: String) -> Int? {
        do {
            let fileAccess = RadrootsAppleFileAccess(roots: roots)
            let swept = try fileAccess.sweepStagedBlobs(
                olderThan: now().addingTimeInterval(-Self.stagedBlobRetention)
            )
            telemetry.backgroundExecution(
                operation: "staged_blob_sweep",
                outcome: "success",
                stagedBlobCount: swept.count,
                reason: reason
            )
            return swept.count
        } catch {
            telemetry.backgroundExecution(
                operation: "staged_blob_sweep",
                outcome: FieldTelemetry.backgroundExecutionOutcome(for: error),
                reason: reason
            )
            return nil
        }
    }

    private func refreshRelaysIfAllowed(reason: String) async -> Bool {
        guard identityUnlocked else {
            telemetry.backgroundExecution(
                operation: "relay_refresh",
                outcome: "skipped_locked",
                identityUnlocked: false,
                reason: reason
            )
            return true
        }
        guard let runtimeService else {
            telemetry.backgroundExecution(
                operation: "relay_refresh",
                outcome: "skipped_runtime_unavailable",
                identityUnlocked: true,
                reason: reason
            )
            return true
        }
        do {
            try await runtimeService.nostrSetDefaultRelays(try RelaySettings.relays())
            try await runtimeService.nostrConnectIfKeyPresent()
            let status = await runtimeService.nostrConnectionStatus()
            telemetry.backgroundExecution(
                operation: "relay_refresh",
                outcome: "success",
                relayConnectedCount: status.connected,
                relayConnectingCount: status.connecting,
                identityUnlocked: true,
                reason: reason
            )
            return true
        } catch {
            telemetry.backgroundExecution(
                operation: "relay_refresh",
                outcome: FieldTelemetry.backgroundExecutionOutcome(for: error),
                identityUnlocked: true,
                reason: reason
            )
            return false
        }
    }

}
