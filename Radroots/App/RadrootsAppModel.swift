import Foundation
import RadrootsKit

@MainActor
final class RadrootsAppModel: ObservableObject {
    typealias Phase = RadrootsSessionPhase

    @Published private(set) var phase: Phase = .starting
    private(set) var todayStore: RadrootsTodayStore?
    private(set) var addStore: RadrootsAddStore?
    private(set) var searchStore: RadrootsSearchStore?
    private(set) var meStore: RadrootsMeStore?
    let diagnosticsStore: RadrootsDiagnosticsStore

    private let sessionStore: RadrootsSessionStore?
    private let bootstrapFailure: RadrootsRuntimeFailure?
    private let lifecycleCoordinator: RadrootsLifecycleCoordinator
    private var generation: UInt64 = 0
    private var lifecycleRegistered = false
    private var sessionOperationsInFlight = 0
    private var resumePending = false
    private let isShellUITest: Bool

    init(
        sessionStore: RadrootsSessionStore? = nil,
        runtimeClient: RadrootsRuntimeClient? = nil,
        lifecycleCoordinator requestedLifecycleCoordinator: RadrootsLifecycleCoordinator? = nil
    ) {
        let lifecycleCoordinator =
            requestedLifecycleCoordinator
                ?? Bundle.main.bundleIdentifier.flatMap {
                    try? RadrootsLifecycleCoordinator.production(bundleIdentifier: $0)
                }
                ?? RadrootsLifecycleCoordinator.disabled()
        self.lifecycleCoordinator = lifecycleCoordinator
        diagnosticsStore = RadrootsDiagnosticsStore(coordinator: lifecycleCoordinator)
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
                let sessionStore = try RadrootsSessionStore.production(
                    runtimeClient: runtimeClient
                )
                let mediaCoordinator = try Self.productionMediaCoordinator()
                self.sessionStore = sessionStore
                todayStore = RadrootsTodayStore(runtimeClient: runtimeClient)
                addStore = RadrootsAddStore(
                    runtimeClient: runtimeClient,
                    media: mediaCoordinator
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
        await ensureLifecycleRegistration()
        await lifecycleCoordinator.record("ios.lifecycle.start_requested")
        await run(name: "start", showsStarting: true) { store in await store.start() }
    }

    func retry() async {
        await start()
    }

    func createIdentity() async {
        await run(name: "identity_create", showsStarting: true) { store in
            await store.createIdentity()
        }
    }

    func unlockIdentity() async {
        await run(name: "identity_unlock", showsStarting: true) { store in
            await store.unlockIdentity()
        }
    }

    func recoverIdentity() async {
        await run(name: "identity_recover", showsStarting: true) { store in
            await store.recoverIdentity()
        }
    }

    func applyConfigurationReconfiguration() async {
        await run(name: "configuration_reconfigure", showsStarting: true) { store in
            await store.applyConfigurationReconfiguration()
        }
    }

    func stop() async {
        stopPresentationWork()
        await run(name: "stop") { store in await store.stop() }
    }

    func resume() async {
        await ensureLifecycleRegistration()
        guard sessionOperationsInFlight == 0 else {
            resumePending = true
            await lifecycleCoordinator.record("ios.lifecycle.resume_coalesced")
            return
        }
        resumePending = false
        if case .running = phase {
            await todayStore?.start()
            await addStore?.start()
            await lifecycleCoordinator.record("ios.lifecycle.active")
        } else {
            await start()
        }
    }

    func suspend() async {
        generation &+= 1
        resumePending = false
        todayStore?.stop()
        addStore?.suspend()
        searchStore?.stop()
        meStore?.stop()
        await sessionStore?.suspend()
        await lifecycleCoordinator.record("ios.lifecycle.background")
    }

    func updateProtectedDataAvailability(_ available: Bool) async {
        await sessionStore?.updateProtectedDataAvailability(available)
        await lifecycleCoordinator.record(
            available
                ? "ios.lifecycle.protected_data_available"
                : "ios.lifecycle.protected_data_unavailable"
        )
        if available {
            await start()
        } else {
            await stop()
            await start()
        }
    }

    func shutdown() async {
        await lifecycleCoordinator.record("ios.lifecycle.shutdown_requested", level: .notice)
        await stop()
        await RadrootsBackgroundEventRouter.shared.detachAndCompletePending()
    }

    private func run(
        name: String,
        showsStarting: Bool = false,
        _ operation: @escaping @Sendable (RadrootsSessionStore) async -> Phase
    ) async {
        guard !isShellUITest else { return }
        sessionOperationsInFlight += 1
        generation &+= 1
        let requestedGeneration = generation
        if showsStarting {
            phase = .starting
        }
        guard let sessionStore else {
            phase = .failed(
                bootstrapFailure
                    ?? .local(
                        operation: "app.bootstrap",
                        code: "ios.app.bootstrap_failed",
                        safeMessage: "Radroots could not start."
                    )
            )
            await lifecycleCoordinator.record(
                "ios.lifecycle.operation_failed",
                level: .error,
                fields: ["operation": name, "code": "bootstrap_failed"]
            )
            await finishSessionOperation()
            return
        }
        let result = await operation(sessionStore)
        guard generation == requestedGeneration else {
            await finishSessionOperation()
            return
        }
        if case let .running(snapshot) = result {
            todayStore?.configure(snapshot: snapshot)
            addStore?.configure(snapshot: snapshot)
        }
        phase = result
        await lifecycleCoordinator.record(
            "ios.lifecycle.operation_completed",
            level: Self.isFailure(result) ? .warning : .info,
            fields: ["operation": name, "phase": Self.phaseCode(result)]
        )
        await finishSessionOperation()
    }

    private func finishSessionOperation() async {
        sessionOperationsInFlight -= 1
        guard sessionOperationsInFlight == 0, resumePending else { return }
        resumePending = false
        await resume()
    }

    private func ensureLifecycleRegistration() async {
        guard !lifecycleRegistered else { return }
        lifecycleRegistered = true
        await lifecycleCoordinator.attachBackgroundEvents()
        await RadrootsLifecycleBridge.shared.register { @Sendable [weak self] in
            await self?.shutdown()
        }
    }

    private func stopPresentationWork() {
        todayStore?.stop()
        addStore?.stop()
        searchStore?.stop()
        meStore?.stop()
    }

    private static func isFailure(_ phase: Phase) -> Bool {
        if case .failed = phase {
            return true
        }
        return false
    }

    private static func phaseCode(_ phase: Phase) -> String {
        switch phase {
        case .starting: "starting"
        case .identityRequired: "identity_required"
        case .identityLocked: "identity_locked"
        case .protectedDataUnavailable: "protected_data_unavailable"
        case .recoveryRequired: "recovery_required"
        case .corruptIdentity: "corrupt_identity"
        case .configurationReconfigurationRequired: "configuration_reconfiguration_required"
        case .running: "running"
        case .stopped: "stopped"
        case .failed: "failed"
        }
    }

    private static func productionMediaCoordinator(
        bundle: Bundle = .main
    ) throws -> RadrootsAddMediaCoordinator {
        guard let bundleIdentifier = bundle.bundleIdentifier else {
            throw RadrootsConfigurationError.missing("bundle_identifier")
        }
        return try RadrootsAddMediaCoordinator.production(bundleIdentifier: bundleIdentifier)
    }
}

#if DEBUG
    fileprivate extension RadrootsRuntimeSnapshot {
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
            blossomConfiguration: nil,
            blossomEvidence: nil,
            crateName: "radroots_mobile_ffi",
            crateVersion: "0.1.0-alpha",
            isClosed: false
        )
    }
#endif
