import Foundation

struct LoggingSettings: Equatable {
    var stdout: Bool
    var fileEnabled: Bool
    var fileName: String
    var level: String?

    static func load() -> LoggingSettings {
        let stdout = BuildConfig.bool(.logStdout) ?? true
        let fileEnabled = BuildConfig.bool(.logFileEnabled) ?? false
        let fileName = BuildConfig.string(.logFileName) ?? "radroots.log"
        let level = BuildConfig.string(.logLevel)
        return LoggingSettings(stdout: stdout, fileEnabled: fileEnabled, fileName: fileName, level: level)
    }

    func apply() throws {
        if let level {
            setenv("RUST_LOG", level, 1)
        }
        if fileEnabled {
            let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!.path
            try initLogging(dir: dir, fileName: fileName, isStdout: stdout)
        } else {
            try initLogging(dir: nil, fileName: fileName, isStdout: stdout)
        }
    }

    func logEffectiveConfigs() {
        let keys: [BuildConfigKey] = [.logStdout, .logLevel, .logFileEnabled, .logFileName, .nostrRelays]
        let dict = BuildConfig.effectiveDictionary(keys: keys)
        let json = (try? JSONSerialization.data(withJSONObject: dict, options: [.sortedKeys])) ?? Data()
        let text = String(data: json, encoding: .utf8) ?? String(describing: dict)
        try? logInfo(msg: "radroots.config \(text)")
    }
}
