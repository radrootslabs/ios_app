import Foundation

@MainActor
public final class Radroots: ObservableObject {
    public private(set) var runtime: RadrootsRuntime?

    public init() {}

    public func start(
        bundleId: String = Bundle.main.bundleIdentifier ?? "unknown",
        version: String = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "0",
        build: String = (Bundle.main.infoDictionary?["CFBundleVersion"] as? String) ?? "0",
        buildSha: String? = nil
    ) throws {
        try initLoggingIfNeeded()
        let rt = try RadrootsRuntime()
        rt.setAppInfoPlatform(
            platform: "iOS",
            bundleId: bundleId,
            version: version,
            buildNumber: build,
            buildSha: buildSha
        )
        self.runtime = rt
    }

    deinit {
        runtime?.stop()
    }

    public func info() -> RuntimeInfo? {
        runtime?.info()
    }

    private func initLoggingIfNeeded() throws {
        if (try? initLoggingStdout()) == nil {
            let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!.path
            try initLogging(dir: dir, fileName: "radroots.log", isStdout: true)
        }
    }
}
