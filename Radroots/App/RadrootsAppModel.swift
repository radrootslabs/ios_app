import Foundation

@MainActor
final class RadrootsAppModel: ObservableObject {
    typealias Phase = RadrootsSessionPhase

    @Published private(set) var phase: Phase = .starting
    private(set) var todayStore: RadrootsTodayStore?
    private(set) var addStore: RadrootsAddStore?
    private(set) var searchStore: RadrootsSearchStore?
    private(set) var meStore: RadrootsMeStore?

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
                addStore = nil
                searchStore = nil
                meStore = nil
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
            addStore = runtimeClient.map { RadrootsAddStore(runtimeClient: $0) }
            searchStore = runtimeClient.map { RadrootsSearchStore(runtimeClient: $0) }
            meStore = runtimeClient.map { RadrootsMeStore(runtimeClient: $0) }
            bootstrapFailure = nil
        } else {
            do {
                let runtimeClient = runtimeClient ?? .production()
                self.sessionStore = try .production(runtimeClient: runtimeClient)
                todayStore = RadrootsTodayStore(runtimeClient: runtimeClient)
                addStore = RadrootsAddStore(
                    runtimeClient: runtimeClient,
                    media: Self.productionMediaCoordinator()
                )
                searchStore = RadrootsSearchStore(runtimeClient: runtimeClient)
                meStore = RadrootsMeStore(runtimeClient: runtimeClient)
                bootstrapFailure = nil
            } catch let error as LocalizedError {
                self.sessionStore = nil
                todayStore = nil
                addStore = nil
                searchStore = nil
                meStore = nil
                bootstrapFailure = .local(
                    operation: "app.bootstrap",
                    code: "ios.app.configuration_invalid",
                    safeMessage: error.errorDescription ?? "Radroots configuration is invalid."
                )
            } catch {
                self.sessionStore = nil
                todayStore = nil
                addStore = nil
                searchStore = nil
                meStore = nil
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
            addStore?.configure(snapshot: snapshot)
        }
        phase = result
    }

    private static func productionMediaCoordinator(bundle: Bundle = .main) -> RadrootsAddMediaCoordinator? {
        guard let bundleIdentifier = bundle.bundleIdentifier,
              let origin = configuredValues("RADROOTS_FIELD_IOS_BLOSSOM_ORIGINS", bundle: bundle).first,
              let url = URL(string: origin)
        else {
            return nil
        }
        return try? RadrootsAddMediaCoordinator.production(
            bundleIdentifier: bundleIdentifier,
            blossomOrigin: url
        )
    }

    private static func configuredValues(_ key: String, bundle: Bundle) -> [String] {
        if let values = bundle.object(forInfoDictionaryKey: key) as? [String] {
            return values.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }
        guard let value = bundle.object(forInfoDictionaryKey: key) as? String else { return [] }
        return value.components(separatedBy: CharacterSet(charactersIn: ",; \n\r\t"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
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
