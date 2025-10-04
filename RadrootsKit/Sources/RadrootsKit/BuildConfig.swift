import Foundation

enum BuildConfigKey: String {
    case logStdout = "RR_LOG_STDOUT"
    case logLevel = "RR_LOG_LEVEL"
    case logFileEnabled = "RR_LOG_FILE_ENABLED"
    case logFileName = "RR_LOG_FILE_NAME"
    case nostrRelays = "NOSTR_RELAYS"
}

enum BuildConfig {
    static func string(_ key: BuildConfigKey) -> String? {
        let info = infoString(key).map { stripOuterQuotes($0) }
        let env = ProcessInfo.processInfo.environment[key.rawValue]
            .flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .flatMap { $0.isEmpty ? nil : stripOuterQuotes($0) }
        return info ?? env
    }

    static func bool(_ key: BuildConfigKey) -> Bool? {
        if let v = infoValue(for: key.rawValue) {
            if let b = v as? Bool { return b }
            if let s = v as? String, let parsed = parseBool(s) { return parsed }
            if let n = v as? NSNumber { return n.boolValue }
        }
        if let env = ProcessInfo.processInfo.environment[key.rawValue],
           let parsed = parseBool(env) {
            return parsed
        }
        return nil
    }

    static func array(_ key: BuildConfigKey, splitBy set: CharacterSet = .whitespacesAndNewlines) -> [String]? {
        if let direct = infoArray(key) {
            return direct
                .map { stripOuterQuotes($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }
        guard var raw = string(key)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty else { return nil }
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

    static func effectiveDictionary(keys: [BuildConfigKey]) -> [String: Any] {
        var out: [String: Any] = [:]
        for k in keys {
            if let b = bool(k) {
                out[k.rawValue] = b
            } else if k == .nostrRelays, let arr = array(.nostrRelays) {
                out[k.rawValue] = arr
            } else if let s = string(k) {
                out[k.rawValue] = s
            }
        }
        return out
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
