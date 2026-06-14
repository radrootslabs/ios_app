import Foundation
import RadrootsKit

enum FieldAppRuntimeError: LocalizedError {
    case runtimeNotReady
    case forcedStartupFailure

    var errorDescription: String? {
        switch self {
        case .runtimeNotReady:
            "Runtime not ready. Please retry."
        case .forcedStartupFailure:
            "Startup failure requested by field iOS runtime mode."
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
    @Published public private(set) var storedIdentityAvailable: Bool = false
    @Published public private(set) var runtimeIdentityReady: Bool = false
    @Published public private(set) var isLocked: Bool = false
    @Published public private(set) var npub: String?
    @Published public private(set) var identityLabel: String?
    @Published public private(set) var identities: [NostrIdentityRecord] = []
    @Published public private(set) var relayConnectedCount: UInt32 = 0
    @Published public private(set) var relayConnectingCount: UInt32 = 0
    @Published public private(set) var relayLight: RelayLight = .red
    @Published public private(set) var relayLastError: String?
    @Published public private(set) var fileAccessProbeValue: String?

    public var canShowAppContent: Bool {
        bootstrapPhase == .ready && runtimeIdentityReady && !isLocked
    }

    public var requiresSetup: Bool {
        bootstrapPhase == .ready && (!storedIdentityAvailable || isLocked || !runtimeIdentityReady)
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
    private var secureIdentityStore: FieldSecureIdentityStore?
    private var identityMetadataStore: FieldIdentityPublicMetadataStore?

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
            try await holdBootstrapSplashForUITestIfRequested()
            if startupFailureWasRequested {
                throw FieldAppRuntimeError.forcedStartupFailure
            }
            let service = try radroots.start()
            let secureStore = try FieldSecureIdentityStore.configured()
            let metadataStore = try FieldIdentityPublicMetadataStore.configured()
            let appBundleIdentifier = try bundleIdentifier()
            let resetLocalStateRequested = BuildConfig.bool(.resetLocalState) == true
            try FieldFileAccessUITestProbe.seedDestructiveResetSentinelIfRequested(
                bundleIdentifier: appBundleIdentifier,
                resetLocalStateRequested: resetLocalStateRequested
            )
            secureIdentityStore = secureStore
            identityMetadataStore = metadataStore
            if resetLocalStateRequested {
                try FieldLocalState.resetFileRoots(bundleIdentifier: appBundleIdentifier)
                try secureStore.deleteSelectedSecret()
                metadataStore.delete()
                try await resetRuntimeIdentityState(using: service)
                applyNoIdentity()
                setLocked(false)
            } else {
                loadStoredIdentityMetadata(metadataStore)
            }
            try await refreshRuntimeState(using: service)
            if runtimeIdentityReady && !isLocked {
                try await connect(using: service)
                startPollingStatus()
            }
            try refreshFileAccessProbe(
                bundleIdentifier: appBundleIdentifier,
                resetLocalStateRequested: resetLocalStateRequested,
                identityResetObserved: false
            )
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
        try await restoreStoredIdentity(using: service)
        setLocked(false)
        try await connect(using: service)
        await refreshRuntimeState(using: service)
        startPollingStatus()
    }

    public func createLocalIdentity() async throws {
        let service = try requireRuntimeService()
        try await createHostCustodyIdentity(using: service)
        setLocked(false)
        try await connect(using: service)
        await refreshRuntimeState(using: service)
        startPollingStatus()
    }

    public func importNostrSecret(_ secretKey: String) async throws {
        let trimmed = secretKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let service = try requireRuntimeService()
        let record = try await secureIdentityStoreOrConfigured().importSecret(
            trimmed,
            label: "Imported Field Identity",
            using: service
        )
        try persistIdentity(record)
        setLocked(false)
        try await connect(using: service)
        await refreshRuntimeState(using: service)
        startPollingStatus()
    }

    public func signOut() {
        setLocked(true)
        statusTask?.cancel()
        statusTask = nil
        relayConnectedCount = 0
        relayConnectingCount = 0
        relayLight = .red
        Task {
            await lockRuntimeIdentity()
        }
    }

    public func resetLocalIdentity() async throws {
        let service = try requireRuntimeService()
        try secureIdentityStoreOrConfigured().deleteSelectedSecret()
        try identityMetadataStoreOrConfigured().delete()
        try await resetRuntimeIdentityState(using: service)
        applyNoIdentity()
        setLocked(false)
        relayConnectedCount = 0
        relayConnectingCount = 0
        relayLight = .red
        relayLastError = nil
        await refreshRuntimeState(using: service)
        try refreshFileAccessProbe(
            bundleIdentifier: try bundleIdentifier(),
            resetLocalStateRequested: false,
            identityResetObserved: true
        )
        statusTask?.cancel()
        statusTask = nil
    }

    public func requireRuntimeService() throws -> FieldRuntimeService {
        guard let service = runtimeService else {
            throw FieldAppRuntimeError.runtimeNotReady
        }
        return service
    }

    func prepareDiagnosticsDocumentExport() throws -> RadrootsPreparedExportDocument {
        try documentInterchange().prepareDiagnosticsExport(
            infoJSONString: infoJSONString,
            relays: RelaySettings.relays(),
            connectedCount: relayConnectedCount,
            connectingCount: relayConnectingCount,
            lastError: relayLastError
        )
    }

    func prepareRelayConfigDocumentExport() throws -> RadrootsPreparedExportDocument {
        try documentInterchange().prepareRelayConfigExport(relays: RelaySettings.relays())
    }

    func importedRelayConfig(from importedDocument: RadrootsImportedDocument) throws -> [String] {
        try documentInterchange().importedRelayConfig(from: importedDocument)
    }

    func publicPostShareRequest(content: String) throws -> RadrootsShareRequest {
        try documentInterchange().publicPostShareRequest(content: content)
    }

    func documentFileAccess() throws -> RadrootsAppleFileAccess {
        try FieldLocalState.fileAccess(bundleIdentifier: bundleIdentifier())
    }

    func releasePreparedDocumentExport(_ preparedExport: RadrootsPreparedExportDocument) {
        try? documentFileAccess().releasePreparedExport(preparedExport)
    }

    private func documentInterchange() throws -> FieldDocumentInterchange {
        try FieldDocumentInterchange(bundleIdentifier: bundleIdentifier())
    }

    private var isFailed: Bool {
        if case .failed = bootstrapPhase {
            return true
        }
        return false
    }

    private var uiTestWasRequested: Bool {
        let arguments = ProcessInfo.processInfo.arguments
        let environment = ProcessInfo.processInfo.environment
        return environment["RADROOTS_FIELD_IOS_UI_TEST"] == "true" ||
            arguments.contains("--radroots-field-ios-ui-test")
    }

    private var uiTestBootstrapSplashHoldNanoseconds: UInt64? {
        guard uiTestWasRequested else { return nil }
        guard let raw = ProcessInfo.processInfo.environment["RADROOTS_FIELD_IOS_UI_TEST_BOOTSTRAP_SPLASH_HOLD_SECONDS"],
              let seconds = Double(raw),
              seconds.isFinite,
              seconds > 0 else {
            return nil
        }
        return UInt64(seconds * 1_000_000_000)
    }

    private func holdBootstrapSplashForUITestIfRequested() async throws {
        guard let nanoseconds = uiTestBootstrapSplashHoldNanoseconds else { return }
        try await Task.sleep(nanoseconds: nanoseconds)
    }

    private var startupFailureWasRequested: Bool {
        guard uiTestWasRequested else {
            return false
        }
        let arguments = ProcessInfo.processInfo.arguments
        let environment = ProcessInfo.processInfo.environment
        if BuildConfig.string(.runtimeMode) == "ui-test-startup-failure" {
            return true
        }
        if environment["RADROOTS_FIELD_IOS_FORCE_STARTUP_FAILURE"] == "true" {
            return true
        }
        return arguments.contains("--radroots-field-ios-force-startup-failure")
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
        runtimeIdentityReady = snapshot.hasSelectedSigningIdentity
        identities = snapshot.identities
        if snapshot.hasSelectedSigningIdentity {
            storedIdentityAvailable = true
            hasKey = true
            npub = snapshot.selectedNpub
            identityLabel = snapshot.identities.first(where: { $0.isSelected })?.label
        } else if storedIdentityAvailable {
            hasKey = true
        } else {
            hasKey = false
            npub = nil
            identityLabel = nil
        }
    }

    private func lockRuntimeIdentityState(using service: FieldRuntimeService) async throws {
        try await service.nostrIdentityLockHostCustodyRuntime()
        runtimeIdentityReady = false
        identities = []
    }

    private func resetRuntimeIdentityState(using service: FieldRuntimeService) async throws {
        try await service.nostrIdentityResetHostCustodyRuntime()
        runtimeIdentityReady = false
        identities = []
    }

    private func loadStoredIdentityMetadata(_ metadataStore: FieldIdentityPublicMetadataStore) {
        guard let metadata = metadataStore.load() else {
            applyNoIdentity()
            setLocked(false)
            return
        }
        apply(storedIdentity: metadata)
        setLocked(true)
    }

    private func restoreStoredIdentity(using service: FieldRuntimeService) async throws {
        let existingMetadata = try identityMetadataStoreOrConfigured().load()
        let record = try await secureIdentityStoreOrConfigured().restoreStoredIdentity(
            label: existingMetadata?.label ?? "Radroots Field",
            using: service
        )
        try persistIdentity(record)
    }

    private func createHostCustodyIdentity(using service: FieldRuntimeService) async throws {
        let record = try await secureIdentityStoreOrConfigured().createIdentity(
            label: "Radroots Field",
            using: service
        )
        try persistIdentity(record)
    }

    private func persistIdentity(_ record: NostrIdentityRecord) throws {
        let metadata = FieldIdentityPublicMetadata(record: record)
        try identityMetadataStoreOrConfigured().save(metadata)
        apply(storedIdentity: metadata)
        runtimeIdentityReady = true
        hasKey = true
        identities = [record]
    }

    private func lockRuntimeIdentity() async {
        guard let service = runtimeService else {
            runtimeIdentityReady = false
            identities = []
            hasKey = storedIdentityAvailable
            return
        }
        do {
            try await lockRuntimeIdentityState(using: service)
        } catch {
            relayLastError = error.localizedDescription
        }
        hasKey = storedIdentityAvailable
        await refreshRelayStatus(using: service)
    }

    private func apply(storedIdentity metadata: FieldIdentityPublicMetadata) {
        storedIdentityAvailable = true
        hasKey = true
        npub = metadata.publicKeyNpub
        identityLabel = metadata.label
    }

    private func applyNoIdentity() {
        hasKey = false
        storedIdentityAvailable = false
        runtimeIdentityReady = false
        npub = nil
        identityLabel = nil
        identities = []
    }

    private func secureIdentityStoreOrConfigured() throws -> FieldSecureIdentityStore {
        if let secureIdentityStore {
            return secureIdentityStore
        }
        let configured = try FieldSecureIdentityStore.configured()
        secureIdentityStore = configured
        return configured
    }

    private func identityMetadataStoreOrConfigured() throws -> FieldIdentityPublicMetadataStore {
        if let identityMetadataStore {
            return identityMetadataStore
        }
        let configured = try FieldIdentityPublicMetadataStore.configured()
        identityMetadataStore = configured
        return configured
    }

    private func bundleIdentifier() throws -> String {
        guard let bundleIdentifier = Bundle.main.bundleIdentifier,
              !bundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw FieldSecureIdentityStoreError.missingBundleIdentifier
        }
        return bundleIdentifier
    }

    private func refreshFileAccessProbe(
        bundleIdentifier: String,
        resetLocalStateRequested: Bool,
        identityResetObserved: Bool
    ) throws {
        let loggingSettings = LoggingSettings.load()
        if identityResetObserved {
            fileAccessProbeValue = try FieldFileAccessUITestProbe.identityResetValue(
                bundleIdentifier: bundleIdentifier,
                loggingFileEnabled: loggingSettings.fileEnabled,
                loggingFileName: loggingSettings.fileName
            )
        } else {
            fileAccessProbeValue = try FieldFileAccessUITestProbe.startupValue(
                bundleIdentifier: bundleIdentifier,
                resetLocalStateRequested: resetLocalStateRequested,
                loggingFileEnabled: loggingSettings.fileEnabled,
                loggingFileName: loggingSettings.fileName
            )
        }
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
