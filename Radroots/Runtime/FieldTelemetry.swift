import Foundation
import RadrootsKit

final class FieldTelemetry: @unchecked Sendable {
    static let shared = FieldTelemetry.configured()

    private let sink: any RadrootsTelemetry
    private let minimumLevel: RadrootsTelemetryLevel
    private let recordedEventsProvider: (@Sendable () async -> [RadrootsTelemetryEvent])?

    init(
        sink: any RadrootsTelemetry,
        minimumLevel: RadrootsTelemetryLevel = .info,
        recordedEventsProvider: (@Sendable () async -> [RadrootsTelemetryEvent])? = nil
    ) {
        self.sink = sink
        self.minimumLevel = minimumLevel
        self.recordedEventsProvider = recordedEventsProvider
    }

    static func configured(
        bundleIdentifier: String = Bundle.main.bundleIdentifier ?? "dev.local.radroots",
        loggingSettings: LoggingSettings = .load()
    ) -> FieldTelemetry {
        let minimumLevel = telemetryMinimumLevel(from: loggingSettings.level)
        let appleTelemetry = RadrootsAppleLoggerTelemetry(subsystem: bundleIdentifier)
        #if DEBUG
        if FieldUITestHarness.isRequested {
            let recorder = FieldUITestRecordingTelemetry()
            return FieldTelemetry(
                sink: RadrootsMultiplexTelemetry([appleTelemetry, recorder]),
                minimumLevel: minimumLevel,
                recordedEventsProvider: { await recorder.recordedEvents }
            )
        }
        #endif
        return FieldTelemetry(sink: appleTelemetry, minimumLevel: minimumLevel)
    }

    func record(
        name: String,
        category: String = "field_ios",
        level: RadrootsTelemetryLevel = .info,
        message: String? = nil,
        fields: [RadrootsTelemetryField] = []
    ) {
        Task {
            await recordAsync(
                name: name,
                category: category,
                level: level,
                message: message,
                fields: fields
            )
        }
    }

    func recordAsync(
        name: String,
        category: String = "field_ios",
        level: RadrootsTelemetryLevel = .info,
        message: String? = nil,
        fields: [RadrootsTelemetryField] = []
    ) async {
        guard level >= minimumLevel else {
            return
        }
        guard let event = try? RadrootsTelemetryEvent(
            name: name,
            category: category,
            level: level,
            message: message,
            fields: fields
        ) else {
            return
        }
        await sink.record(event)
    }

    func runtimeLoggingInitialized(settings: LoggingSettings) {
        record(
            name: "field_ios.runtime.logging_initialized",
            level: .info,
            fields: [
                try? .bool("stdout_enabled", settings.stdout),
                try? .bool("file_enabled", settings.fileEnabled),
                try? .string("logging_filter", settings.level ?? "unset"),
            ].compactMap { $0 }
        )
    }

    func appStartupBegan() {
        record(name: "field_ios.startup.begin", level: .notice)
    }

    func appStartupSucceeded(
        storedIdentityAvailable: Bool,
        runtimeIdentityReady: Bool,
        locked: Bool
    ) {
        record(
            name: "field_ios.startup.success",
            level: .notice,
            fields: [
                try? .bool("stored_identity_available", storedIdentityAvailable),
                try? .bool("runtime_identity_ready", runtimeIdentityReady),
                try? .bool("identity_locked", locked)
            ].compactMap { $0 }
        )
    }

    func appStartupFailed(_ error: Error) {
        record(
            name: "field_ios.startup.failure",
            level: .error,
            fields: [
                try? .string("outcome", Self.outcome(for: error))
            ].compactMap { $0 }
        )
    }

    func relayStatusChanged(
        connectedCount: UInt32,
        connectingCount: UInt32,
        configuredRelayCount: Int,
        light: String
    ) {
        record(
            name: "field_ios.relay.status_changed",
            level: light == "red" ? .warning : .info,
            fields: [
                try? .integer("connected_count", Int64(connectedCount)),
                try? .integer("connecting_count", Int64(connectingCount)),
                try? .integer("configured_relay_count", configuredRelayCount),
                try? .string("relay_light", light)
            ].compactMap { $0 }
        )
    }

    func identityCustody(action: String, outcome: String) {
        record(
            name: "field_ios.identity_custody.\(action)",
            level: outcome == "success" ? .info : .warning,
            fields: [
                try? .string("outcome", outcome)
            ].compactMap { $0 }
        )
    }

    func userPresence(action: FieldUserPresenceAction, outcome: String) {
        record(
            name: "field_ios.user_presence.\(action.telemetryName)",
            level: outcome == "success" ? .info : .warning,
            fields: [
                try? .string("outcome", outcome)
            ].compactMap { $0 }
        )
    }

    func captureSupportRefreshed(
        support: FieldCaptureSupportState,
        recordCount: Int,
        outcome: String
    ) {
        record(
            name: "field_ios.capture.support_refreshed",
            level: outcome == "success" ? .info : .warning,
            fields: [
                try? .string("outcome", outcome),
                try? .bool("photo_import_available", support.photoImportAvailable),
                try? .bool("camera_photo_available", support.cameraPhotoAvailable),
                try? .bool("document_scanner_available", support.documentScannerAvailable),
                try? .integer("record_count", recordCount)
            ].compactMap { $0 }
        )
    }

    func captureOperation(
        operation: FieldCaptureIntakeOperation,
        outcome: String,
        recordCount: Int,
        recoveryAction: FieldExternalActionRecovery?
    ) {
        record(
            name: "field_ios.capture.\(operation.telemetryName)",
            level: outcome == "success" ? .info : .warning,
            fields: [
                try? .string("outcome", outcome),
                try? .integer("record_count", recordCount),
                recoveryAction.map { try? .string("recovery_action", $0.rawValue) } ?? nil
            ].compactMap { $0 }
        )
    }

    func documentInterchange(operation: String, outcome: String, relayCount: Int? = nil) {
        record(
            name: "field_ios.document_interchange.\(operation)",
            level: outcome == "success" ? .info : .warning,
            fields: [
                try? .string("outcome", outcome),
                relayCount.map { try? .integer("relay_count", $0) } ?? nil
            ].compactMap { $0 }
        )
    }

    func externalAction(
        operation: String,
        kind: RadrootsExternalActionDestinationKind?,
        outcome: String
    ) {
        record(
            name: "field_ios.external_action.\(operation)",
            level: outcome == "success" ? .info : .warning,
            fields: [
                try? .string("outcome", outcome),
                kind.map { try? .string("destination_kind", $0.rawValue) } ?? nil
            ].compactMap { $0 }
        )
    }

    func backgroundExecution(
        operation: String,
        outcome: String,
        taskCount: Int? = nil,
        stagedBlobCount: Int? = nil,
        transferCount: Int? = nil,
        relayConnectedCount: UInt32? = nil,
        relayConnectingCount: UInt32? = nil,
        identityUnlocked: Bool? = nil,
        reason: String? = nil
    ) {
        let expectedOutcome = outcome == "success" || outcome.hasPrefix("skipped")
        var fields: [RadrootsTelemetryField] = []
        if let field = try? RadrootsTelemetryField.string("outcome", outcome) {
            fields.append(field)
        }
        if let taskCount,
           let field = try? RadrootsTelemetryField.integer("task_count", taskCount) {
            fields.append(field)
        }
        if let stagedBlobCount,
           let field = try? RadrootsTelemetryField.integer("staged_blob_count", stagedBlobCount) {
            fields.append(field)
        }
        if let transferCount,
           let field = try? RadrootsTelemetryField.integer("transfer_count", transferCount) {
            fields.append(field)
        }
        if let relayConnectedCount,
           let field = try? RadrootsTelemetryField.integer("relay_connected_count", Int64(relayConnectedCount)) {
            fields.append(field)
        }
        if let relayConnectingCount,
           let field = try? RadrootsTelemetryField.integer("relay_connecting_count", Int64(relayConnectingCount)) {
            fields.append(field)
        }
        if let identityUnlocked,
           let field = try? RadrootsTelemetryField.bool("identity_unlocked", identityUnlocked) {
            fields.append(field)
        }
        if let reason,
           let field = try? RadrootsTelemetryField.string("reason", reason) {
            fields.append(field)
        }
        record(
            name: "field_ios.background_execution.\(operation)",
            level: expectedOutcome ? .info : .warning,
            fields: fields
        )
    }

    func recordedEventsForUITest() async -> [RadrootsTelemetryEvent] {
        guard let recordedEventsProvider else {
            return []
        }
        return await recordedEventsProvider()
    }

    private static func telemetryMinimumLevel(from filter: String?) -> RadrootsTelemetryLevel {
        guard let filter else {
            return .info
        }
        let lowered = filter.lowercased()
        if lowered.contains("trace") {
            return .trace
        }
        if lowered.contains("debug") {
            return .debug
        }
        if lowered.contains("info") {
            return .info
        }
        if lowered.contains("notice") {
            return .notice
        }
        if lowered.contains("warn") {
            return .warning
        }
        if lowered.contains("error") {
            return .error
        }
        if lowered.contains("critical") || lowered.contains("fault") {
            return .critical
        }
        return .info
    }

    private static func outcome(for error: Error) -> String {
        if let error = error as? FieldAppRuntimeError {
            switch error {
            case .forcedStartupFailure:
                return "forced_failure"
            case .runtimeNotReady:
                return "runtime_not_ready"
            }
        }
        if let error = error as? RelaySettingsError {
            switch error {
            case .noRelaysConfigured:
                return "relay_config_missing"
            case .invalidRelayURL:
                return "invalid_relay_url"
            case .invalidStoredRelaySettings:
                return "invalid_relay_settings"
            }
        }
        switch error {
        case FieldUserPresenceGateError.notVerified:
            return "unverified"
        case is FieldRuntimeLoggingError:
            return "logging_initialization_failed"
        case let error as RadrootsUserPresenceError:
            return userPresenceOutcome(for: error)
        case let error as RadrootsCaptureIntakeError:
            return captureOutcome(for: error)
        case let error as RadrootsExternalActionError:
            return externalActionOutcome(for: error)
        case let error as FieldDocumentInterchangeError:
            return documentInterchangeOutcome(for: error)
        default:
            return "failure"
        }
    }

    static func userPresenceOutcome(for error: Error) -> String {
        if let error = error as? FieldUserPresenceGateError {
            switch error {
            case .notVerified:
                return "unverified"
            }
        }
        guard let error = error as? RadrootsUserPresenceError else {
            return "failure"
        }
        switch error {
        case .userCancelled:
            return "cancelled"
        case .permissionDenied:
            return "denied"
        case .unavailable:
            return "unavailable"
        case .timeout:
            return "timeout"
        case .transientFailure:
            return "transient_failure"
        case .permanentFailure:
            return "permanent_failure"
        case .invalidRequest:
            return "invalid_request"
        }
    }

    static func captureOutcome(for error: Error) -> String {
        guard let error = error as? RadrootsCaptureIntakeError else {
            return "failure"
        }
        switch error {
        case .userCancelled:
            return "cancelled"
        case .permissionDenied:
            return "denied"
        case .unavailable:
            return "unavailable"
        case .transientFailure:
            return "transient_failure"
        case .permanentFailure:
            return "permanent_failure"
        case .invalidRequest:
            return "invalid_request"
        }
    }

    static func backgroundExecutionOutcome(for error: Error) -> String {
        switch error {
        case let error as RadrootsBackgroundTaskError:
            switch error {
            case .invalidRequest:
                return "invalid_request"
            case .unavailable:
                return "unavailable"
            case .schedulerFailure:
                return "scheduler_failure"
            }
        case let error as RadrootsBackgroundTransferError:
            switch error {
            case .invalidRequest:
                return "invalid_request"
            case .unavailable:
                return "unavailable"
            case .transferFailure:
                return "transfer_failure"
            case .persistenceFailure:
                return "persistence_failure"
            }
        case let error as RadrootsAppleFileError:
            switch error {
            case .invalidRequest:
                return "invalid_request"
            case .notFound:
                return "not_found"
            case .permissionDenied:
                return "permission_denied"
            case .transientFailure:
                return "transient_failure"
            case .permanentFailure:
                return "permanent_failure"
            }
        case let error as RelaySettingsError:
            switch error {
            case .noRelaysConfigured:
                return "relay_config_missing"
            case .invalidRelayURL:
                return "invalid_relay_url"
            case .invalidStoredRelaySettings:
                return "invalid_relay_settings"
            }
        default:
            return "failure"
        }
    }

    static func externalActionOutcome(for error: Error) -> String {
        guard let error = error as? RadrootsExternalActionError else {
            return "failure"
        }
        switch error {
        case .invalidRequest:
            return "invalid_request"
        case .blockedByPolicy:
            return "blocked_by_policy"
        case .unavailable:
            return "unavailable"
        case .transientFailure:
            return "transient_failure"
        case .permanentFailure:
            return "permanent_failure"
        }
    }

    static func documentInterchangeOutcome(for error: Error) -> String {
        guard let error = error as? FieldDocumentInterchangeError else {
            return "failure"
        }
        switch error {
        case .emptyRelayConfig:
            return "empty_relay_config"
        case .invalidRelayURL:
            return "invalid_relay_url"
        case .invalidRelayConfigDocument:
            return "invalid_relay_config_document"
        }
    }
}

extension FieldUserPresenceAction {
    var telemetryName: String {
        switch self {
        case .unlockIdentity:
            return "unlock_identity"
        case .saveIdentity:
            return "save_identity"
        case .deleteIdentity:
            return "delete_identity"
        }
    }
}

extension FieldCaptureIntakeOperation {
    var telemetryName: String {
        switch self {
        case .idle:
            return "idle"
        case .refreshing:
            return "support_refresh"
        case .importingPhoto:
            return "import_photo"
        case .capturingPhoto:
            return "capture_photo"
        case .scanningDocument:
            return "scan_document"
        }
    }
}
