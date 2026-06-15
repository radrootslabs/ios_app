import Foundation
import RadrootsKit

enum FieldTelemetryUITestProbe {
    private static let enabledKey = "RADROOTS_FIELD_IOS_UI_TEST_TELEMETRY_PROBE"
    private static let redactionPolicy = RadrootsTelemetryRedactionPolicy.default

    static var isRequested: Bool {
        ProcessInfo.processInfo.environment[enabledKey] == "true"
    }

    static func value(recordedBy telemetry: FieldTelemetry) async -> String? {
        guard isRequested else {
            return nil
        }
        let events = await telemetry.recordedEventsForUITest()
        return value(events: events)
    }

    private static func value(events: [RadrootsTelemetryEvent]) -> String {
        let eventNames = Set(events.map(\.name))
        let fieldKeys = Set(events.flatMap { event in
            event.fields.map(\.key)
        })
        let values = events.flatMap(stringValues)
        return [
            "event_count=\(events.count)",
            "event_names=\(eventNames.sorted().joined(separator: ","))",
            "field_keys=\(fieldKeys.sorted().joined(separator: ","))",
            "runtime_logging_seen=\(eventNames.contains("field_ios.runtime.logging_initialized"))",
            "startup_success_seen=\(eventNames.contains("field_ios.startup.success"))",
            "relay_status_seen=\(eventNames.contains("field_ios.relay.status_changed"))",
            "identity_create_seen=\(eventNames.contains("field_ios.identity_custody.create"))",
            "user_presence_save_identity_seen=\(eventNames.contains("field_ios.user_presence.save_identity"))",
            "document_diagnostics_export_seen=\(eventNames.contains("field_ios.document_interchange.diagnostics_export"))",
            "document_relay_config_export_seen=\(eventNames.contains("field_ios.document_interchange.relay_config_export"))",
            "document_relay_config_import_seen=\(eventNames.contains("field_ios.document_interchange.relay_config_import"))",
            "document_public_share_prepare_seen=\(eventNames.contains("field_ios.document_interchange.public_share_prepare"))",
            "capture_support_refreshed_seen=\(eventNames.contains("field_ios.capture.support_refreshed"))",
            "capture_import_photo_seen=\(eventNames.contains("field_ios.capture.import_photo"))",
            "capture_scan_document_seen=\(eventNames.contains("field_ios.capture.scan_document"))",
            "external_action_open_seen=\(eventNames.contains("field_ios.external_action.open"))",
            "unsafe_values_present=\(values.contains(where: containsUnsafeValue))",
            "relay_url_values_present=\(values.contains(where: containsRelayURL))",
            "secret_like_values_present=\(values.contains(where: containsSecretLikeValue))",
            "path_like_values_present=\(values.contains(where: containsPathLikeValue))",
            "npub_values_present=\(values.contains(where: containsNpubValue))"
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
