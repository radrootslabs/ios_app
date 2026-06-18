import Foundation
import RadrootsKit

public enum RelaySettingsError: LocalizedError {
    case noRelaysConfigured
    case invalidRelayURL(String)
    case invalidStoredRelaySettings

    public var errorDescription: String? {
        switch self {
        case .noRelaysConfigured:
            "No Nostr relays configured. Set 'RADROOTS_FIELD_IOS_NOSTR_RELAY_URLS'."
        case .invalidRelayURL(let value):
            "Invalid Nostr relay URL: \(value)."
        case .invalidStoredRelaySettings:
            "Stored Nostr relay settings are invalid."
        }
    }
}

public enum RelaySettingsSource: String {
    case buildConfig
    case userImported

    var displayName: String {
        switch self {
        case .buildConfig:
            "Build Config"
        case .userImported:
            "Imported"
        }
    }
}

public struct RelaySettingsSnapshot: Equatable {
    public let source: RelaySettingsSource
    public let relays: [String]
}

public enum RelaySettings {
    private struct StoredRelaySettingsDocument: Codable {
        static let format = "radroots_field_ios_relay_settings_v1"

        let format: String
        let relays: [String]
    }

    private static let storedSettingsFile = RadrootsFileReference(
        scope: .data,
        relativePath: "settings/relay_settings.json"
    )

    public static func relays() throws -> [String] {
        guard let parts = BuildConfig.array(.nostrRelayUrls) else {
            throw RelaySettingsError.noRelaysConfigured
        }
        return try validatedRelays(parts)
    }

    public static func effectiveSnapshot(bundleIdentifier: String) throws -> RelaySettingsSnapshot {
        if let importedRelays = try userImportedRelays(bundleIdentifier: bundleIdentifier) {
            return RelaySettingsSnapshot(source: .userImported, relays: importedRelays)
        }
        return RelaySettingsSnapshot(source: .buildConfig, relays: try relays())
    }

    @discardableResult
    public static func storeUserImportedRelays(
        _ relays: [String],
        bundleIdentifier: String
    ) throws -> RelaySettingsSnapshot {
        let normalized = try validatedRelays(relays)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let document = StoredRelaySettingsDocument(
            format: StoredRelaySettingsDocument.format,
            relays: normalized
        )
        let data = try encoder.encode(document)
        try FieldLocalState.fileAccess(bundleIdentifier: bundleIdentifier).write(
            .inline(data),
            to: storedSettingsFile
        )
        return RelaySettingsSnapshot(source: .userImported, relays: normalized)
    }

    public static func clearUserImportedRelays(bundleIdentifier: String) throws {
        try FieldLocalState.fileAccess(bundleIdentifier: bundleIdentifier).delete(storedSettingsFile)
    }

    public static func validatedRelays(_ urls: [String]) throws -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for u in urls {
            let trimmed = u.trimmingCharacters(in: .whitespacesAndNewlines)
            let unquoted = trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            guard !unquoted.isEmpty else {
                continue
            }
            guard let components = URLComponents(string: unquoted),
                  let scheme = components.scheme?.lowercased(),
                  scheme == "ws" || scheme == "wss",
                  components.host != nil,
                  unquoted.rangeOfCharacter(from: .whitespacesAndNewlines) == nil else {
                throw RelaySettingsError.invalidRelayURL(u)
            }
            let lower = unquoted.lowercased()
            if seen.insert(lower).inserted {
                out.append(unquoted)
            }
        }
        guard !out.isEmpty else {
            throw RelaySettingsError.noRelaysConfigured
        }
        return out
    }

    private static func userImportedRelays(bundleIdentifier: String) throws -> [String]? {
        do {
            let result = try FieldLocalState.fileAccess(bundleIdentifier: bundleIdentifier).read(
                storedSettingsFile,
                mode: .inline
            )
            guard case .inline(let data) = result else {
                throw RelaySettingsError.invalidStoredRelaySettings
            }
            let document = try JSONDecoder().decode(StoredRelaySettingsDocument.self, from: data)
            guard document.format == StoredRelaySettingsDocument.format else {
                throw RelaySettingsError.invalidStoredRelaySettings
            }
            return try validatedRelays(document.relays)
        } catch RadrootsAppleFileError.notFound(_) {
            return nil
        } catch is DecodingError {
            throw RelaySettingsError.invalidStoredRelaySettings
        }
    }
}
