import Foundation
import RadrootsKit
import RadrootsKitTesting

final class FieldTelemetry: @unchecked Sendable {
    static let shared = FieldTelemetry.configured()

    private let sink: any RadrootsTelemetry
    private let minimumLevel: RadrootsTelemetryLevel
    private let recordingTelemetry: RadrootsRecordingTelemetry?

    init(
        sink: any RadrootsTelemetry,
        minimumLevel: RadrootsTelemetryLevel = .info,
        recordingTelemetry: RadrootsRecordingTelemetry? = nil
    ) {
        self.sink = sink
        self.minimumLevel = minimumLevel
        self.recordingTelemetry = recordingTelemetry
    }

    static func configured(
        bundleIdentifier: String = Bundle.main.bundleIdentifier ?? "dev.local.radroots",
        loggingSettings: LoggingSettings = .load()
    ) -> FieldTelemetry {
        let minimumLevel = telemetryMinimumLevel(from: loggingSettings.level)
        let appleTelemetry = RadrootsAppleLoggerTelemetry(subsystem: bundleIdentifier)
        if uiTestWasRequested {
            let recorder = RadrootsRecordingTelemetry()
            return FieldTelemetry(
                sink: RadrootsMultiplexTelemetry([appleTelemetry, recorder]),
                minimumLevel: minimumLevel,
                recordingTelemetry: recorder
            )
        }
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

    func runtimeLoggingInitialized(
        settings: LoggingSettings,
        fallbackUsed: Bool
    ) {
        record(
            name: "field_ios.runtime.logging_initialized",
            level: fallbackUsed ? .warning : .info,
            fields: [
                try? .bool("stdout_enabled", settings.stdout),
                try? .bool("file_enabled", settings.fileEnabled),
                try? .string("logging_filter", settings.level ?? "unset"),
                try? .bool("fallback_used", fallbackUsed)
            ].compactMap { $0 }
        )
    }

    func recordedEventsForUITest() async -> [RadrootsTelemetryEvent] {
        guard let recordingTelemetry else {
            return []
        }
        return await recordingTelemetry.recordedEvents
    }

    private static var uiTestWasRequested: Bool {
        let environment = ProcessInfo.processInfo.environment
        let arguments = ProcessInfo.processInfo.arguments
        return environment["RADROOTS_FIELD_IOS_UI_TEST"] == "true" ||
            arguments.contains("--radroots-field-ios-ui-test")
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
}
