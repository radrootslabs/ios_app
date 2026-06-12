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
        let settings = LoggingSettings.load()
        do {
            try settings.apply()
        } catch {
            try? initLoggingStdout()
        }
        settings.logEffectiveConfigs()

        let rt = try RadrootsRuntime()
        let resolvedSha = buildSha ?? (Bundle.main.object(forInfoDictionaryKey: "GIT_SHA") as? String)
        rt.setAppInfoPlatform(
            platform: "iOS",
            bundleId: bundleId,
            version: version,
            buildNumber: build,
            buildSha: resolvedSha
        )
        self.runtime = rt
    }

    deinit {
        runtime?.stop()
    }

    public func info() -> RuntimeInfo? {
        runtime?.info()
    }
}
