import Foundation

@MainActor
final class RadrootsAppModel: ObservableObject {
    typealias Phase = RadrootsSessionPhase

    @Published private(set) var phase: Phase = .starting

    private let sessionStore: RadrootsSessionStore?
    private let bootstrapFailure: RadrootsRuntimeFailure?
    private var generation: UInt64 = 0

    init(sessionStore: RadrootsSessionStore? = nil) {
        if let sessionStore {
            self.sessionStore = sessionStore
            bootstrapFailure = nil
        } else {
            do {
                self.sessionStore = try .production()
                bootstrapFailure = nil
            } catch let error as LocalizedError {
                self.sessionStore = nil
                bootstrapFailure = .local(
                    operation: "app.bootstrap",
                    code: "ios.app.configuration_invalid",
                    safeMessage: error.errorDescription ?? "Radroots configuration is invalid."
                )
            } catch {
                self.sessionStore = nil
                bootstrapFailure = .local(
                    operation: "app.bootstrap",
                    code: "ios.app.configuration_invalid",
                    safeMessage: "Radroots configuration is invalid."
                )
            }
        }
    }

    func start() async {
        await run { store in await store.start() }
    }

    func retry() async {
        await start()
    }

    func createIdentity() async {
        await run { store in await store.createIdentity() }
    }

    func unlockIdentity() async {
        await run { store in await store.unlockIdentity() }
    }

    func recoverIdentity() async {
        await run { store in await store.recoverIdentity() }
    }

    func stop() async {
        await run { store in await store.stop() }
    }

    private func run(
        _ operation: @escaping @Sendable (RadrootsSessionStore) async -> Phase
    ) async {
        generation &+= 1
        let requestedGeneration = generation
        guard let sessionStore else {
            phase = .failed(
                bootstrapFailure ?? .local(
                    operation: "app.bootstrap",
                    code: "ios.app.bootstrap_failed",
                    safeMessage: "Radroots could not start."
                )
            )
            return
        }
        let result = await operation(sessionStore)
        guard generation == requestedGeneration else { return }
        phase = result
    }
}
