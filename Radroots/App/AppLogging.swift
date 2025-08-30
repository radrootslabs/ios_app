import Foundation
import RadrootsKit

public enum AppLogging {
    public static func configure() {
        let fm = FileManager.default

        do {
            let base = try fm.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )

            let logsDir = base.appendingPathComponent("Logs", isDirectory: true)
            try fm.createDirectory(at: logsDir, withIntermediateDirectories: true)

            _ = try initLogging(
                dir: logsDir.path,
                fileName: "radroots-ios.log",
                isStdout: true
            )
        } catch {
            _ = try? initLoggingStdout()
        }
    }
}
