import Foundation
import RadrootsKit

enum FieldBackgroundExecutionUITestProbe {
    private static let enabledKey = "RADROOTS_FIELD_IOS_UI_TEST_BACKGROUND_EXECUTION_PROBE"
    private static let redactionPolicy = RadrootsTelemetryRedactionPolicy.default

    static var isRequested: Bool {
        ProcessInfo.processInfo.environment[enabledKey] == "true"
    }

    static func value(
        registered: Bool,
        scheduledTaskCount: Int,
        pendingBeforeMaintenance: Int,
        pendingBeforeCancel: Int,
        pendingAfterCancel: Int,
        cancellationObserved: Bool,
        stagedBlobRemoved: Bool,
        transferSnapshotCount: Int,
        events: [RadrootsTelemetryEvent]
    ) -> String {
        let eventNames = Set(events.map(\.name))
        let values = events.flatMap(stringValues)
        return [
            "registered=\(registered)",
            "scheduled_task_count=\(scheduledTaskCount)",
            "schedule_observed=\(scheduledTaskCount >= 2)",
            "pending_before_maintenance=\(pendingBeforeMaintenance)",
            "pending_before_cancel=\(pendingBeforeCancel)",
            "pending_after_cancel=\(pendingAfterCancel)",
            "cancellation_observed=\(cancellationObserved)",
            "staged_blob_removed=\(stagedBlobRemoved)",
            "transfer_snapshot_count=\(transferSnapshotCount)",
            "background_register_seen=\(eventNames.contains("field_ios.background_execution.register"))",
            "background_schedule_seen=\(eventNames.contains("field_ios.background_execution.schedule"))",
            "background_cancel_all_seen=\(eventNames.contains("field_ios.background_execution.cancel_all"))",
            "background_transfer_inspect_seen=\(eventNames.contains("field_ios.background_execution.transfer_inspect"))",
            "background_staged_blob_sweep_seen=\(eventNames.contains("field_ios.background_execution.staged_blob_sweep"))",
            "background_relay_refresh_seen=\(eventNames.contains("field_ios.background_execution.relay_refresh"))",
            "background_maintenance_seen=\(eventNames.contains("field_ios.background_execution.maintenance"))",
            "unsafe_values_present=\(values.contains(where: containsUnsafeValue))",
            "relay_url_values_present=\(values.contains(where: containsRelayURL))",
            "secret_like_values_present=\(values.contains(where: containsSecretLikeValue))",
            "path_like_values_present=\(values.contains(where: containsPathLikeValue))",
            "npub_values_present=\(values.contains(where: containsNpubValue))"
        ].joined(separator: ";")
    }

    static func failureValue(outcome: String) -> String {
        [
            "registered=false",
            "scheduled_task_count=0",
            "pending_before_maintenance=0",
            "pending_before_cancel=0",
            "pending_after_cancel=0",
            "cancellation_observed=false",
            "staged_blob_removed=false",
            "transfer_snapshot_count=0",
            "probe_failure_outcome=\(outcome)",
            "unsafe_values_present=false",
            "relay_url_values_present=false",
            "secret_like_values_present=false",
            "path_like_values_present=false",
            "npub_values_present=false"
        ].joined(separator: ";")
    }

    private static func stringValues(from event: RadrootsTelemetryEvent) -> [String] {
        var values = event.message.map { [$0] } ?? []
        values.append(contentsOf: event.fields.map { field in
            field.value.renderedValue
        })
        return values
    }

    private static func containsUnsafeValue(_ value: String) -> Bool {
        redactionPolicy.containsUnsafeValue(value)
            || containsRelayURL(value)
            || containsSecretLikeValue(value)
            || containsPathLikeValue(value)
            || containsNpubValue(value)
    }

    private static func containsRelayURL(_ value: String) -> Bool {
        let normalized = value.lowercased()
        return normalized.contains("ws://") || normalized.contains("wss://")
    }

    private static func containsSecretLikeValue(_ value: String) -> Bool {
        let normalized = value.lowercased()
        return normalized.contains("nsec")
            || normalized.range(of: "[a-f0-9]{64}", options: .regularExpression) != nil
    }

    private static func containsPathLikeValue(_ value: String) -> Bool {
        let normalized = value.lowercased()
        return normalized.contains("/users/")
            || normalized.contains("/private/var/")
            || normalized.contains("/var/mobile/containers/")
            || normalized.contains("/var/folders/")
            || normalized.contains("file:///")
    }

    private static func containsNpubValue(_ value: String) -> Bool {
        value.lowercased().contains("npub")
    }
}
