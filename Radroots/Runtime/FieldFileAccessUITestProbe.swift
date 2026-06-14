import Foundation
import RadrootsKit

enum FieldFileAccessUITestProbe {
    private static let enabledKey = "RADROOTS_FIELD_IOS_UI_TEST_FILE_ACCESS_PROBE"
    private static let destructiveResetSentinel = RadrootsFileReference(
        scope: .data,
        relativePath: "ui_tests/file_access/destructive_reset_sentinel.txt"
    )
    private static let identityBoundarySentinel = RadrootsFileReference(
        scope: .data,
        relativePath: "ui_tests/file_access/identity_boundary_sentinel.txt"
    )

    static var isRequested: Bool {
        ProcessInfo.processInfo.environment[enabledKey] == "true"
    }

    static func seedDestructiveResetSentinelIfRequested(
        bundleIdentifier: String,
        resetLocalStateRequested: Bool
    ) throws {
        guard isRequested && resetLocalStateRequested else {
            return
        }
        try access(bundleIdentifier: bundleIdentifier).write(
            .inline(Data("destructive-reset-sentinel".utf8)),
            to: destructiveResetSentinel
        )
    }

    static func startupValue(
        bundleIdentifier: String,
        resetLocalStateRequested: Bool,
        loggingFileEnabled: Bool,
        loggingFileName: String
    ) throws -> String? {
        guard isRequested else {
            return nil
        }
        let fileAccess = try access(bundleIdentifier: bundleIdentifier)
        try fileAccess.write(
            .inline(Data("identity-boundary-sentinel".utf8)),
            to: identityBoundarySentinel
        )
        return try value(
            bundleIdentifier: bundleIdentifier,
            resetLocalStateRequested: resetLocalStateRequested,
            identityResetObserved: false,
            loggingFileEnabled: loggingFileEnabled,
            loggingFileName: loggingFileName
        )
    }

    static func identityResetValue(
        bundleIdentifier: String,
        loggingFileEnabled: Bool,
        loggingFileName: String
    ) throws -> String? {
        guard isRequested else {
            return nil
        }
        return try value(
            bundleIdentifier: bundleIdentifier,
            resetLocalStateRequested: false,
            identityResetObserved: true,
            loggingFileEnabled: loggingFileEnabled,
            loggingFileName: loggingFileName
        )
    }

    private static func value(
        bundleIdentifier: String,
        resetLocalStateRequested: Bool,
        identityResetObserved: Bool,
        loggingFileEnabled: Bool,
        loggingFileName: String
    ) throws -> String {
        let fileAccess = try access(bundleIdentifier: bundleIdentifier)
        let resetSentinelExists = try exists(destructiveResetSentinel, using: fileAccess)
        let identitySentinelExists = try exists(identityBoundarySentinel, using: fileAccess)
        let logFileURL = try FieldLocalState.logFileURL(bundleIdentifier: bundleIdentifier, fileName: loggingFileName)
        let logsRoot = try FieldLocalState.roots(bundleIdentifier: bundleIdentifier).root(for: .logs)
        let logURLUnderLogsRoot = logFileURL.path.hasPrefix(logsRoot.path + "/")
        let destructiveResetRemovedSentinel = resetLocalStateRequested ? !resetSentinelExists : true
        return [
            "destructive_reset_removed_sentinel=\(destructiveResetRemovedSentinel)",
            "identity_boundary_sentinel_exists=\(identitySentinelExists)",
            "identity_reset_observed=\(identityResetObserved)",
            "logging_file_enabled=\(loggingFileEnabled)",
            "log_url_under_logs_root=\(logURLUnderLogsRoot)"
        ].joined(separator: ";")
    }

    private static func exists(
        _ file: RadrootsFileReference,
        using fileAccess: RadrootsAppleFileAccess
    ) throws -> Bool {
        do {
            _ = try fileAccess.read(file, mode: .inline)
            return true
        } catch RadrootsAppleFileError.notFound(_) {
            return false
        }
    }

    private static func access(bundleIdentifier: String) throws -> RadrootsAppleFileAccess {
        try FieldLocalState.fileAccess(bundleIdentifier: bundleIdentifier)
    }
}
