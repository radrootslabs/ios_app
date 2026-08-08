import Foundation

@MainActor
final class RadrootsAppModel: ObservableObject {
    typealias Phase = RadrootsSessionPhase

    @Published private(set) var phase: Phase = .starting
    private(set) var todayStore: RadrootsTodayStore?

    private let sessionStore: RadrootsSessionStore?
    private let bootstrapFailure: RadrootsRuntimeFailure?
    private var generation: UInt64 = 0
    private let isShellUITest: Bool

    init(
        sessionStore: RadrootsSessionStore? = nil,
        runtimeClient: RadrootsRuntimeClient? = nil
    ) {
        #if DEBUG
            if ProcessInfo.processInfo.environment["RADROOTS_IOS_UI_TEST_SHELL"] == "1" {
                self.sessionStore = nil
                todayStore = nil
                bootstrapFailure = nil
                isShellUITest = true
                phase = .running(.shellUITest)
                return
            }
        #endif
        isShellUITest = false
        if let sessionStore {
            self.sessionStore = sessionStore
            todayStore = runtimeClient.map { RadrootsTodayStore(runtimeClient: $0) }
            bootstrapFailure = nil
        } else {
            do {
                let runtimeClient = runtimeClient ?? .production()
                self.sessionStore = try .production(runtimeClient: runtimeClient)
                todayStore = RadrootsTodayStore(runtimeClient: runtimeClient)
                bootstrapFailure = nil
            } catch let error as LocalizedError {
                self.sessionStore = nil
                todayStore = nil
                bootstrapFailure = .local(
                    operation: "app.bootstrap",
                    code: "ios.app.configuration_invalid",
                    safeMessage: error.errorDescription ?? "Radroots configuration is invalid."
                )
            } catch {
                self.sessionStore = nil
                todayStore = nil
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
        guard !isShellUITest else { return }
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
        if case let .running(snapshot) = result {
            todayStore?.configure(snapshot: snapshot)
        }
        phase = result
    }
}

#if DEBUG
    private extension RadrootsRuntimeSnapshot {
        static let shellUITest = RadrootsRuntimeSnapshot(
            identity: RadrootsRuntimeIdentity(
                publicKeyHex: String(repeating: "ab", count: 32),
                hostSignerConfigured: true
            ),
            relay: RadrootsRelayStatus(
                profile: "simulator",
                state: "configured",
                readAvailability: "unobserved",
                writeAvailability: "unobserved",
                relays: []
            ),
            crateName: "radroots_mobile_ffi",
            crateVersion: "0.1.0-alpha",
            isClosed: false
        )
    }
#endif
