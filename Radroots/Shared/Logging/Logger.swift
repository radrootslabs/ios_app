import Foundation
import os

private let oslog = os.Logger(subsystem: Bundle.main.bundleIdentifier ?? "Radroots", category: "App")

enum RadrootsLogger {
    static func info(_ message: String) {
        oslog.info("\(message, privacy: .public)")
        do {
            try logInfo(msg: message)
        } catch {
            oslog.error("logInfo failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    static func error(_ message: String) {
        oslog.error("\(message, privacy: .public)")
        do {
            try logError(msg: message)
        } catch {
            oslog.error("logError failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    static func debug(_ message: String) {
        #if DEBUG
        oslog.debug("\(message, privacy: .public)")
        do {
            try logDebug(msg: message)
        } catch {
            oslog.error("logDebug failed: \(error.localizedDescription, privacy: .public)")
        }
        #endif
    }
}
