import Foundation
import RadrootsKit

#if DEBUG
enum FieldUITestHarness {
    static var isRequested: Bool {
        let environment = ProcessInfo.processInfo.environment
        let arguments = ProcessInfo.processInfo.arguments
        return environment["RADROOTS_FIELD_IOS_UI_TEST"] == "true" ||
            arguments.contains("--radroots-field-ios-ui-test")
    }

    static func bool(_ key: String, default defaultValue: Bool) -> Bool {
        guard let raw = ProcessInfo.processInfo.environment[key] else {
            return defaultValue
        }
        switch raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "1", "true", "yes":
            return true
        case "0", "false", "no":
            return false
        default:
            return defaultValue
        }
    }

    static func string(_ key: String) -> String? {
        ProcessInfo.processInfo.environment[key]?.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

actor FieldUITestBackgroundTaskScheduler: RadrootsBackgroundTaskScheduler {
    private var pendingTaskSnapshots: [RadrootsBackgroundTaskIdentifier: RadrootsBackgroundTaskSnapshot]
    private var submittedRequestsValue: [RadrootsBackgroundTaskRequest]
    private var cancelAllCountValue: Int
    private let submittedAt: Date

    init(submittedAt: Date = Date(timeIntervalSince1970: 0)) {
        self.pendingTaskSnapshots = [:]
        self.submittedRequestsValue = []
        self.cancelAllCountValue = 0
        self.submittedAt = submittedAt
    }

    func submit(_ request: RadrootsBackgroundTaskRequest) async throws -> RadrootsBackgroundTaskSnapshot {
        submittedRequestsValue.append(request)
        let snapshot = try RadrootsBackgroundTaskSnapshot(request: request, submittedAt: submittedAt)
        pendingTaskSnapshots[request.identifier] = snapshot
        return snapshot
    }

    func cancel(_ identifier: RadrootsBackgroundTaskIdentifier) async throws {
        pendingTaskSnapshots.removeValue(forKey: identifier)
    }

    func cancelAll() async throws {
        cancelAllCountValue += 1
        pendingTaskSnapshots.removeAll()
    }

    func pendingTasks() async throws -> [RadrootsBackgroundTaskSnapshot] {
        pendingTaskSnapshots.values.sorted { lhs, rhs in
            lhs.identifier < rhs.identifier
        }
    }

    var submittedRequestCount: Int {
        submittedRequestsValue.count
    }

    var cancelAllCount: Int {
        cancelAllCountValue
    }
}

actor FieldUITestBackgroundTransferStore: RadrootsBackgroundTransferStore {
    private var snapshotsByIdentifier: [RadrootsBackgroundTransferIdentifier: RadrootsBackgroundTransferSnapshot] = [:]

    func loadSnapshots() async throws -> [RadrootsBackgroundTransferSnapshot] {
        snapshotsByIdentifier.values.sorted { left, right in
            left.identifier < right.identifier
        }
    }

    func saveSnapshot(_ snapshot: RadrootsBackgroundTransferSnapshot) async throws {
        snapshotsByIdentifier[snapshot.identifier] = snapshot
    }

    func removeSnapshot(for identifier: RadrootsBackgroundTransferIdentifier) async throws {
        snapshotsByIdentifier.removeValue(forKey: identifier)
    }

    func removeAllSnapshots() async throws {
        snapshotsByIdentifier.removeAll()
    }
}

actor FieldUITestBackgroundTransfer: RadrootsBackgroundTransfer {
    private let store: any RadrootsBackgroundTransferStore
    private let updatedAt: Date

    init(
        store: any RadrootsBackgroundTransferStore = FieldUITestBackgroundTransferStore(),
        updatedAt: Date = Date(timeIntervalSince1970: 0)
    ) {
        self.store = store
        self.updatedAt = updatedAt
    }

    func enqueue(_ request: RadrootsBackgroundTransferRequest) async throws -> RadrootsBackgroundTransferHandle {
        let snapshot = try RadrootsBackgroundTransferSnapshot(
            request: request,
            state: .queued,
            updatedAt: updatedAt
        )
        try await store.saveSnapshot(snapshot)
        return RadrootsBackgroundTransferHandle(request: request)
    }

    func cancel(_ identifier: RadrootsBackgroundTransferIdentifier) async throws {
        if let existing = try await store.loadSnapshots().first(where: { $0.identifier == identifier }) {
            let snapshot = try RadrootsBackgroundTransferSnapshot(
                request: existing.request,
                state: .cancelled,
                progress: existing.progress,
                updatedAt: updatedAt
            )
            try await store.saveSnapshot(snapshot)
        }
    }

    func snapshot(for identifier: RadrootsBackgroundTransferIdentifier) async throws -> RadrootsBackgroundTransferSnapshot? {
        try await store.loadSnapshots().first { $0.identifier == identifier }
    }

    func snapshots() async throws -> [RadrootsBackgroundTransferSnapshot] {
        try await store.loadSnapshots()
    }

    func handleEventsForBackgroundURLSession(
        identifier: String,
        completionHandler: @escaping @Sendable () -> Void
    ) async {
        completionHandler()
    }
}

actor FieldUITestMediaPicker: RadrootsMediaPicker {
    private let support: RadrootsMediaPickerSupport
    private let importOutcome: Result<RadrootsMediaImportResult, RadrootsCaptureIntakeError>
    private let captureOutcome: Result<RadrootsMediaCaptureResult, RadrootsCaptureIntakeError>

    init(
        support: RadrootsMediaPickerSupport,
        importOutcome: Result<RadrootsMediaImportResult, RadrootsCaptureIntakeError>,
        captureOutcome: Result<RadrootsMediaCaptureResult, RadrootsCaptureIntakeError>
    ) {
        self.support = support
        self.importOutcome = importOutcome
        self.captureOutcome = captureOutcome
    }

    func currentSupport() async throws -> RadrootsMediaPickerSupport {
        support
    }

    func importMedia(_ request: RadrootsMediaImportRequest) async throws -> RadrootsMediaImportResult {
        switch importOutcome {
        case .success(let result):
            return result
        case .failure(let error):
            throw error
        }
    }

    func captureMedia(_ request: RadrootsMediaCaptureRequest) async throws -> RadrootsMediaCaptureResult {
        switch captureOutcome {
        case .success(let result):
            return result
        case .failure(let error):
            throw error
        }
    }
}

actor FieldUITestDocumentScanner: RadrootsDocumentScanner {
    private let support: RadrootsDocumentScannerSupport
    private let scanOutcome: Result<RadrootsScannedDocument, RadrootsCaptureIntakeError>

    init(
        support: RadrootsDocumentScannerSupport,
        scanOutcome: Result<RadrootsScannedDocument, RadrootsCaptureIntakeError>
    ) {
        self.support = support
        self.scanOutcome = scanOutcome
    }

    func currentSupport() async throws -> RadrootsDocumentScannerSupport {
        support
    }

    func scanDocument(_ request: RadrootsDocumentScanRequest) async throws -> RadrootsScannedDocument {
        switch scanOutcome {
        case .success(let result):
            return result
        case .failure(let error):
            throw error
        }
    }
}

actor FieldUITestExternalActions: RadrootsExternalActions {
    private let defaultCanOpen: Bool
    private let openOutcome: Result<Void, RadrootsExternalActionError>

    init(
        defaultCanOpen: Bool = true,
        openOutcome: Result<Void, RadrootsExternalActionError> = .success(())
    ) {
        self.defaultCanOpen = defaultCanOpen
        self.openOutcome = openOutcome
    }

    func canOpen(_ destination: RadrootsExternalActionDestination) async -> RadrootsExternalActionCapability {
        RadrootsExternalActionCapability(destination: destination, canOpen: defaultCanOpen)
    }

    func open(_ request: RadrootsExternalActionRequest) async throws {
        switch openOutcome {
        case .success:
            return
        case .failure(let error):
            throw error
        }
    }
}

actor FieldUITestUserPresence: RadrootsUserPresence {
    private let statusValue: RadrootsUserPresenceStatus
    private let outcomes: [Result<Bool, RadrootsUserPresenceError>]
    private var requestCount: Int

    init(
        status: RadrootsUserPresenceStatus = RadrootsUserPresenceStatus(
            support: .biometricsOrDeviceCredential,
            biometryKind: .faceID,
            canEvaluateDeviceCredential: true,
            canEvaluateBiometrics: true
        ),
        outcomes: [Result<Bool, RadrootsUserPresenceError>] = [.success(true)]
    ) {
        self.statusValue = status
        self.outcomes = outcomes.isEmpty ? [.success(true)] : outcomes
        self.requestCount = 0
    }

    func currentStatus() async throws -> RadrootsUserPresenceStatus {
        statusValue
    }

    func verify(_ request: RadrootsUserPresenceRequest) async throws -> RadrootsUserPresenceResult {
        let outcome = outcomes[min(requestCount, outcomes.count - 1)]
        requestCount += 1
        switch outcome {
        case .success(let verified):
            return RadrootsUserPresenceResult(policy: request.policy, verified: verified)
        case .failure(let error):
            throw error
        }
    }
}

actor FieldUITestRecordingTelemetry: RadrootsTelemetry {
    private var recordedEventsValue: [RadrootsTelemetryEvent] = []

    func record(_ event: RadrootsTelemetryEvent) async {
        recordedEventsValue.append(event)
    }

    var recordedEvents: [RadrootsTelemetryEvent] {
        recordedEventsValue
    }
}
#endif
