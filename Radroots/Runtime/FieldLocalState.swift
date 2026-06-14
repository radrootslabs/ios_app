import Foundation
import RadrootsKit

enum FieldLocalStateError: LocalizedError {
    case missingBundleIdentifier
    case invalidLogFileName(String)

    var errorDescription: String? {
        switch self {
        case .missingBundleIdentifier:
            "Missing field iOS bundle identifier."
        case .invalidLogFileName(let value):
            "Invalid RADROOTS_FIELD_IOS_LOGGING_FILE_NAME: \(value)."
        }
    }
}

enum FieldLocalState {
    static func roots(bundleIdentifier: String) throws -> RadrootsAppleFileRoots {
        let appIdentifier = try normalizedBundleIdentifier(bundleIdentifier)
        return try RadrootsAppleFileRoots.appContainer(appIdentifier: appIdentifier)
    }

    static func fileAccess(bundleIdentifier: String) throws -> RadrootsAppleFileAccess {
        try RadrootsAppleFileAccess(roots: roots(bundleIdentifier: bundleIdentifier))
    }

    static func logFileURL(bundleIdentifier: String, fileName: String) throws -> URL {
        let normalizedFileName = try normalizedLogFileName(fileName)
        let file = RadrootsFileReference(scope: .logs, relativePath: normalizedFileName)
        return try roots(bundleIdentifier: bundleIdentifier).resolvedURL(for: file)
    }

    static func resetFileRoots(bundleIdentifier: String) throws {
        try fileAccess(bundleIdentifier: bundleIdentifier).resetFileRoots()
    }

    private static func normalizedBundleIdentifier(_ bundleIdentifier: String) throws -> String {
        let trimmed = bundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw FieldLocalStateError.missingBundleIdentifier
        }
        return trimmed
    }

    private static func normalizedLogFileName(_ fileName: String) throws -> String {
        let trimmed = fileName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              !trimmed.contains("/"),
              !trimmed.contains("\\"),
              !trimmed.contains("\0") else {
            throw FieldLocalStateError.invalidLogFileName(fileName)
        }
        return trimmed
    }
}
