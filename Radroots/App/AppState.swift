import Foundation

enum FieldAppSessionError: LocalizedError {
    case runtimeNotReady
    case missingSessionTokenBundle

    var errorDescription: String? {
        switch self {
        case .runtimeNotReady:
            "Runtime not ready. Please relaunch."
        case .missingSessionTokenBundle:
            "The authenticated session did not return tokens."
        }
    }
}

@MainActor
public final class AppState: ObservableObject {
    public enum BootstrapPhase {
        case idle
        case starting
        case ready
    }

    public enum RelayLight {
        case red, yellow, green
    }

    @Published public private(set) var bootstrapPhase: BootstrapPhase = .idle
    @Published public private(set) var infoJSONString: String = ""
    @Published public private(set) var sessionPhase: FieldSessionPhase = .signedOut
    @Published public private(set) var username: String?
    @Published public private(set) var accountDisplayName: String?
    @Published public private(set) var pendingChallenge: FieldLoginChallenge?
    @Published public private(set) var hasKey: Bool = false
    @Published public private(set) var npub: String?
    @Published public private(set) var relayConnectedCount: UInt32 = 0
    @Published public private(set) var relayConnectingCount: UInt32 = 0
    @Published public private(set) var relayLight: RelayLight = .red
    @Published public private(set) var relayLastError: String?

    public var canShowAppContent: Bool {
        bootstrapPhase == .ready && sessionPhase == .authenticated
    }

    public var requiresSetup: Bool {
        bootstrapPhase == .ready && sessionPhase != .authenticated
    }

    public let radroots: Radroots

    private var sessionStore: FieldSessionCredentialStore?
    private var statusTask: Task<Void, Never>?

    public init(radroots: Radroots = Radroots()) {
        self.radroots = radroots
    }

    deinit {
        statusTask?.cancel()
    }

    public func start() async throws {
        guard bootstrapPhase == .idle else { return }
        bootstrapPhase = .starting
        do {
            try radroots.start()
            let store = try FieldSessionCredentialStore()
            sessionStore = store
            if BuildConfig.bool(.resetLocalState) == true {
                try? store.delete()
            }
            if let rt = radroots.runtime {
                try configure(runtime: rt)
                try restoreSessionIfPossible(runtime: rt, store: store)
            }
            refresh()
            bootstrapPhase = .ready
        } catch {
            bootstrapPhase = .idle
            throw error
        }
    }

    public func refresh() {
        guard let rt = radroots.runtime else { return }
        infoJSONString = rt.infoJson()
        apply(snapshot: rt.fieldSessionSnapshot())
    }

    @discardableResult
    public func startLogin(username: String) throws -> FieldLoginChallenge {
        let rt = try requireRuntime()
        let challenge = try rt.fieldStartLogin(username: username)
        apply(snapshot: rt.fieldSessionSnapshot())
        return challenge
    }

    @discardableResult
    public func resendLoginChallenge(challengeId: String) throws -> FieldLoginChallenge {
        let rt = try requireRuntime()
        let challenge = try rt.fieldResendLoginChallenge(challengeId: challengeId)
        apply(snapshot: rt.fieldSessionSnapshot())
        return challenge
    }

    public func verifyLogin(challengeId: String, code: String) throws {
        let rt = try requireRuntime()
        let snapshot = try rt.fieldVerifyLoginChallenge(challengeId: challengeId, code: code)
        apply(snapshot: snapshot)
        guard let tokens = try rt.fieldSessionTokenBundle() else {
            throw FieldAppSessionError.missingSessionTokenBundle
        }
        try sessionStore?.save(tokens)
        prepareAuthenticatedRuntime()
    }

    public func logout() {
        guard let rt = radroots.runtime else { return }
        do {
            _ = try rt.fieldRevokeSession()
        } catch {
            relayLastError = error.localizedDescription
        }
        try? sessionStore?.delete()
        apply(snapshot: rt.fieldClearSession())
        statusTask?.cancel()
        statusTask = nil
    }

    private func configure(runtime: RadrootsRuntime) throws {
        try runtime.fieldConfigureAuth(
            authApiBaseUrl: try AuthSettings.authApiBaseURL(),
            accountsApiBaseUrl: AuthSettings.accountsApiBaseURL()
        )
    }

    private func restoreSessionIfPossible(
        runtime: RadrootsRuntime,
        store: FieldSessionCredentialStore
    ) throws {
        guard let tokens = try store.load() else {
            apply(snapshot: runtime.fieldSessionSnapshot())
            return
        }
        do {
            let snapshot = try runtime.fieldRestoreSession(
                accessToken: tokens.accessToken,
                refreshToken: tokens.refreshToken
            )
            apply(snapshot: snapshot)
            prepareAuthenticatedRuntime()
        } catch {
            try? store.delete()
            apply(snapshot: runtime.fieldClearSession())
        }
    }

    private func prepareAuthenticatedRuntime() {
        guard let rt = radroots.runtime else { return }
        do {
            let snapshot = try rt.fieldPrepareAuthenticatedNostr(relays: try RelaySettings.relays())
            relayLastError = nil
            apply(snapshot: snapshot)
        } catch {
            relayLastError = error.localizedDescription
        }
        startPollingStatus()
    }

    private func startPollingStatus() {
        statusTask?.cancel()
        statusTask = Task { [weak self] in
            while !Task.isCancelled {
                await MainActor.run { self?.refreshRelayStatus() }
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
    }

    private func refreshRelayStatus() {
        guard let rt = radroots.runtime else { return }
        apply(snapshot: rt.fieldSessionSnapshot())
    }

    private func apply(snapshot: FieldSessionSnapshot) {
        sessionPhase = snapshot.phase
        pendingChallenge = snapshot.pendingChallenge
        username = snapshot.account?.username
        accountDisplayName = snapshot.account?.displayName
        npub = snapshot.selectedNpub
        hasKey = snapshot.selectedNpub != nil
        relayConnectedCount = snapshot.nostrConnected
        relayConnectingCount = snapshot.nostrConnecting
        relayLastError = snapshot.nostrLastError ?? relayLastError

        switch snapshot.nostrLight {
        case .green:
            relayLight = .green
        case .yellow:
            relayLight = .yellow
        case .red:
            relayLight = .red
        @unknown default:
            relayLight = .red
        }
    }

    private func requireRuntime() throws -> RadrootsRuntime {
        guard let rt = radroots.runtime else {
            throw FieldAppSessionError.runtimeNotReady
        }
        return rt
    }
}
