import Foundation
import RadrootsKit

@MainActor
final class AppState: ObservableObject {
    private let radroots = Radroots()

    @Published private(set) var runtimeInfo: RuntimeInfo?
    @Published private(set) var error: Error?

    init() {
        Task { @MainActor in
            await self.startRuntime()
        }
    }

    func infoJSON() async -> String {
        await MainActor.run { [radroots] in
            radroots.runtime?.infoJson() ?? "{}"
        }
    }

    private func startRuntime() async {
        do {
            try radroots.start(
                bundleId: Bundle.main.bundleIdentifier ?? "unknown",
                version: Bundle.main.version ?? "0",
                build: Bundle.main.buildNumber ?? "0",
                buildSha: Bundle.main.buildSHA
            )
            runtimeInfo = radroots.info()
            RadrootsLogger.info("Radroots runtime started successfully")
        } catch {
            self.error = error
            RadrootsLogger.error("Failed to start Radroots runtime: \(error.localizedDescription)")
        }
    }
}
