import Foundation

public enum RelaySettingsError: LocalizedError {
    case noRelaysConfigured

    public var errorDescription: String? {
        "No Nostr relays configured. Set build setting 'NOSTR_RELAYS'."
    }
}

public enum RelaySettings {
    public static func relays() throws -> [String] {
        guard let parts = BuildConfig.array(.nostrRelays) else {
            throw RelaySettingsError.noRelaysConfigured
        }
        let normalized = normalize(parts)
        guard !normalized.isEmpty else {
            throw RelaySettingsError.noRelaysConfigured
        }
        return normalized
    }

    private static func normalize(_ urls: [String]) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for u in urls {
            let trimmed = u.trimmingCharacters(in: .whitespacesAndNewlines)
            let unquoted = trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            let lower = unquoted.lowercased()
            guard lower.hasPrefix("ws://") || lower.hasPrefix("wss://") else { continue }
            if seen.insert(lower).inserted {
                out.append(unquoted)
            }
        }
        return out
    }
}
