import Foundation

struct LoggingSettings: Equatable {
    var stdout: Bool
    var fileEnabled: Bool
    var fileName: String
    var level: String?

    static func load() -> LoggingSettings {
        let stdout = BuildConfig.bool(.loggingStdout) ?? true
        let fileEnabled = BuildConfig.bool(.loggingFileEnabled) ?? false
        let fileName = BuildConfig.string(.loggingFileName) ?? "field-ios.log"
        let level = BuildConfig.string(.loggingFilter)
        return LoggingSettings(stdout: stdout, fileEnabled: fileEnabled, fileName: fileName, level: level)
    }

    func apply(bundleIdentifier: String) throws {
        if let level {
            setenv("RUST_LOG", level, 1)
        }
        if fileEnabled {
            let logFileURL = try FieldLocalState.logFileURL(bundleIdentifier: bundleIdentifier, fileName: fileName)
            try initLogging(
                dir: logFileURL.deletingLastPathComponent().path,
                fileName: logFileURL.lastPathComponent,
                isStdout: stdout
            )
        } else {
            try initLogging(dir: nil, fileName: fileName, isStdout: stdout)
        }
    }
}
