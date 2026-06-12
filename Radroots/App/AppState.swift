import Foundation

enum FieldAppRuntimeError: LocalizedError {
    case runtimeNotReady

    var errorDescription: String? {
        switch self {
        case .runtimeNotReady:
            "Runtime not ready. Please retry."
        }
    }
}

@MainActor
public final class AppState: ObservableObject {
    public enum BootstrapPhase: Equatable {
        case idle
        case starting
        case ready
        case failed(String)
    }

    public enum RelayLight {
        case red, yellow, green
    }

    @Published public private(set) var bootstrapPhase: BootstrapPhase = .idle
    @Published public private(set) var infoJSONString: String = ""
    @Published public private(set) var hasKey: Bool = false
    @Published public private(set) var isLocked: Bool = false
    @Published public private(set) var npub: String?
    @Published public private(set) var identityLabel: String?
    @Published public private(set) var identities: [NostrIdentityRecord] = []
    @Published public private(set) var relayConnectedCount: UInt32 = 0
    @Published public private(set) var relayConnectingCount: UInt32 = 0
    @Published public private(set) var relayLight: RelayLight = .red
    @Published public private(set) var relayLastError: String?

    public var canShowAppContent: Bool {
        bootstrapPhase == .ready && hasKey && !isLocked
    }

    public var requiresSetup: Bool {
        bootstrapPhase == .ready && (!hasKey || isLocked)
    }

    public var identityDisplayName: String {
        if let label = identityLabel?.trimmingCharacters(in: .whitespacesAndNewlines),
           !label.isEmpty {
            return label
        }
        if let npub {
            return shortNpub(npub)
        }
        return "Local Nostr identity"
    }

    public let radroots: Radroots

    public var runtimeService: FieldRuntimeService? {
        radroots.runtimeService
    }

    private let lockKey = "field_ios.identity_locked"
    private var statusTask: Task<Void, Never>?

    public init(radroots: Radroots = Radroots()) {
        self.radroots = radroots
        self.isLocked = UserDefaults.standard.bool(forKey: lockKey)
    }

    deinit {
        statusTask?.cancel()
    }

    public func start() async throws {
        guard bootstrapPhase == .idle || isFailed else { return }
        bootstrapPhase = .starting
        do {
            let service = try radroots.start()
            if BuildConfig.bool(.resetLocalState) == true {
                try await removeAllIdentities(using: service)
                setLocked(false)
            }
            try await configureRelays(using: service)
            try await refreshRuntimeState(using: service)
            if hasKey && !isLocked {
                try await connect(using: service)
                startPollingStatus()
            }
            bootstrapPhase = .ready
        } catch {
            statusTask?.cancel()
            statusTask = nil
            let message = error.localizedDescription
            bootstrapPhase = .failed(message)
            throw error
        }
    }

    public func retryStartup() {
        bootstrapPhase = .idle
        Task {
            try? await start()
        }
    }

    public func refresh() {
        Task {
            await refreshRuntimeState()
        }
    }

    public func continueWithLocalIdentity() async throws {
        let service = try requireRuntimeService()
        setLocked(false)
        try await connect(using: service)
        await refreshRuntimeState(using: service)
        startPollingStatus()
    }

    public func createLocalIdentity() async throws {
        let service = try requireRuntimeService()
        _ = try await service.nostrIdentityGenerate(label: "Radroots Field", makeSelected: true)
        setLocked(false)
        try await connect(using: service)
        await refreshRuntimeState(using: service)
        startPollingStatus()
    }

    public func importNostrSecret(_ secretKey: String) async throws {
        let trimmed = secretKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let service = try requireRuntimeService()
        _ = try await service.nostrIdentityImportSecret(
            secretKey: trimmed,
            label: "Imported Field Identity",
            makeSelected: true
        )
        setLocked(false)
        try await connect(using: service)
        await refreshRuntimeState(using: service)
        startPollingStatus()
    }

    public func signOut() {
        setLocked(true)
        statusTask?.cancel()
        statusTask = nil
    }

    public func resetLocalIdentity() async throws {
        let service = try requireRuntimeService()
        try await removeAllIdentities(using: service)
        setLocked(false)
        relayConnectedCount = 0
        relayConnectingCount = 0
        relayLight = .red
        relayLastError = nil
        await refreshRuntimeState(using: service)
        statusTask?.cancel()
        statusTask = nil
    }

    public func requireRuntimeService() throws -> FieldRuntimeService {
        guard let service = runtimeService else {
            throw FieldAppRuntimeError.runtimeNotReady
        }
        return service
    }

    private var isFailed: Bool {
        if case .failed = bootstrapPhase {
            return true
        }
        return false
    }

    private func configureRelays(using service: FieldRuntimeService) async throws {
        try await service.nostrSetDefaultRelays(try RelaySettings.relays())
    }

    private func connect(using service: FieldRuntimeService) async throws {
        try await configureRelays(using: service)
        try await service.nostrConnectIfKeyPresent()
        await refreshRelayStatus(using: service)
        relayLastError = nil
    }

    private func refreshRuntimeState() async {
        guard let service = runtimeService else { return }
        await refreshRuntimeState(using: service)
    }

    private func refreshRuntimeState(using service: FieldRuntimeService) async {
        infoJSONString = await service.infoJson()
        do {
            let snapshot = try await service.nostrIdentitySnapshot()
            apply(identity: snapshot)
        } catch {
            relayLastError = error.localizedDescription
        }
        await refreshRelayStatus(using: service)
    }

    private func refreshRelayStatus(using service: FieldRuntimeService) async {
        let status = await service.nostrConnectionStatus()
        relayConnectedCount = status.connected
        relayConnectingCount = status.connecting
        relayLastError = status.lastError ?? relayLastError
        switch status.light {
        case .green:
            relayLight = .green
        case .yellow:
            relayLight = .yellow
        case .red:
            relayLight = .red
        }
    }

    private func apply(identity snapshot: NostrIdentitySnapshot) {
        hasKey = snapshot.hasSelectedSigningIdentity
        npub = snapshot.selectedNpub
        identities = snapshot.identities
        identityLabel = snapshot.identities.first(where: { $0.isSelected })?.label
    }

    private func removeAllIdentities(using service: FieldRuntimeService) async throws {
        let existing = try await service.nostrIdentityList()
        for identity in existing {
            try await service.nostrIdentityRemove(identityId: identity.id)
        }
        hasKey = false
        npub = nil
        identityLabel = nil
        identities = []
    }

    private func setLocked(_ value: Bool) {
        isLocked = value
        UserDefaults.standard.set(value, forKey: lockKey)
    }

    private func startPollingStatus() {
        statusTask?.cancel()
        statusTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refreshRuntimeState()
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
    }

    private func shortNpub(_ value: String) -> String {
        guard value.count > 18 else { return value }
        return "\(value.prefix(12))...\(value.suffix(6))"
    }
}
