import Foundation

enum BuildConfigKey: String {
    case envFile = "RADROOTS_FIELD_IOS_ENV_FILE"
    case runtimeMode = "RADROOTS_FIELD_IOS_RUNTIME_MODE"
    case loggingStdout = "RADROOTS_FIELD_IOS_LOGGING_STDOUT"
    case loggingFilter = "RADROOTS_FIELD_IOS_LOGGING_FILTER"
    case loggingFileEnabled = "RADROOTS_FIELD_IOS_LOGGING_FILE_ENABLED"
    case loggingFileName = "RADROOTS_FIELD_IOS_LOGGING_FILE_NAME"
    case nostrRelayUrls = "RADROOTS_FIELD_IOS_NOSTR_RELAY_URLS"
    case authApiBaseUrl = "RADROOTS_FIELD_IOS_AUTH_API_BASE_URL"
    case accountsApiBaseUrl = "RADROOTS_FIELD_IOS_ACCOUNTS_API_BASE_URL"
    case keychainServicePrefix = "RADROOTS_FIELD_IOS_KEYCHAIN_SERVICE_PREFIX"
    case resetLocalState = "RADROOTS_FIELD_IOS_RESET_LOCAL_STATE"
    case tradeRhiPubkey = "RADROOTS_FIELD_IOS_TRADE_RHI_PUBKEY"
}

enum BuildConfig {
    static func string(_ key: BuildConfigKey) -> String? {
        envString(key) ?? infoString(key).map { stripOuterQuotes($0) }
    }

    static func bool(_ key: BuildConfigKey) -> Bool? {
        if let env = ProcessInfo.processInfo.environment[key.rawValue],
           let parsed = parseBool(env) {
            return parsed
        }
        if let v = infoValue(for: key.rawValue) {
            if let b = v as? Bool { return b }
            if let s = v as? String, let parsed = parseBool(s) { return parsed }
            if let n = v as? NSNumber { return n.boolValue }
        }
        return nil
    }

    static func array(_ key: BuildConfigKey, splitBy set: CharacterSet = .whitespacesAndNewlines) -> [String]? {
        if let raw = envString(key) {
            return parseArray(raw, splitBy: set)
        }
        if let direct = infoArray(key) {
            return direct
                .map { stripOuterQuotes($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }
        guard let raw = infoString(key) else { return nil }
        return parseArray(raw, splitBy: set)
    }

    static func effectiveDictionary(keys: [BuildConfigKey]) -> [String: Any] {
        var out: [String: Any] = [:]
        for k in keys {
            switch k {
            case .loggingStdout, .loggingFileEnabled, .resetLocalState:
                if let b = bool(k) {
                    out[k.rawValue] = b
                }
            case .nostrRelayUrls:
                if let arr = array(.nostrRelayUrls) {
                    out[k.rawValue] = arr
                }
            default:
                if let s = string(k) {
                    out[k.rawValue] = s
                }
            }
        }
        return out
    }

    private static func envString(_ key: BuildConfigKey) -> String? {
        ProcessInfo.processInfo.environment[key.rawValue]
            .flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .flatMap { $0.isEmpty ? nil : stripOuterQuotes($0) }
    }

    private static func parseArray(_ value: String, splitBy set: CharacterSet) -> [String]? {
        var raw = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return nil }
        if raw.first == "[" {
            if let data = raw.data(using: .utf8),
               let arr = try? JSONSerialization.jsonObject(with: data) as? [String] {
                return arr
                    .map { stripOuterQuotes($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
            }
        }
        raw = stripOuterQuotes(raw)
        let separators = set.union(CharacterSet(charactersIn: ",;"))
        raw = raw.replacingOccurrences(of: "\n", with: " ")
                 .replacingOccurrences(of: "\r", with: " ")
        return raw
            .components(separatedBy: separators)
            .map { stripOuterQuotes($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func infoString(_ key: BuildConfigKey) -> String? {
        if let v = infoValue(for: key.rawValue) as? String, !v.isEmpty { return v }
        if let n = infoValue(for: key.rawValue) as? NSNumber { return n.stringValue }
        return nil
    }

    private static func infoArray(_ key: BuildConfigKey) -> [String]? {
        if let v = infoValue(for: key.rawValue) as? [String] { return v }
        if let nested = Bundle.main.object(forInfoDictionaryKey: "Radroots") as? [String: Any],
           let v = nested[key.rawValue] as? [String] {
            return v
        }
        return nil
    }

    private static func infoValue(for key: String) -> Any? {
        if let v = Bundle.main.object(forInfoDictionaryKey: key) {
            return v
        }
        if let nested = Bundle.main.object(forInfoDictionaryKey: "Radroots") as? [String: Any] {
            return nested[key]
        }
        return nil
    }

    private static func parseBool(_ s: String) -> Bool? {
        switch s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "1", "true", "yes": return true
        case "0", "false", "no": return false
        default: return nil
        }
    }

    private static func stripOuterQuotes(_ s: String) -> String {
        guard s.count >= 2 else { return s }
        if (s.hasPrefix("\"") && s.hasSuffix("\"")) || (s.hasPrefix("'") && s.hasSuffix("'")) {
            return String(s.dropFirst().dropLast())
        }
        return s
    }
}
