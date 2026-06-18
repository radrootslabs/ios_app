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
    @Published public private(set) var configuredRelayURLs: [String] = []
    @Published public private(set) var relaySettingsSourceLabel: String = RelaySettingsSource.buildConfig.displayName
    @Published public private(set) var fileAccessProbeValue: String?
    @Published public private(set) var documentInterchangeProbeValue: String?
    @Published public private(set) var identityPolicyProbeValue: String?
    @Published public private(set) var telemetryProbeValue: String?
    @Published public private(set) var backgroundExecutionProbeValue: String?
    @Published public private(set) var externalActionStatus: String?
    @Published public private(set) var userPresenceStatus: String?
    @Published public private(set) var canOpenNostrProfile: Bool = false
    @Published public private(set) var locationCheckInState: FieldLocationCheckInState = .idle(
        RadrootsLocationServicesAvailability(locationServicesEnabled: false, authorization: .unavailable)
    )
    @Published public private(set) var captureIntakeState: FieldCaptureIntakeState = .idle

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
    private let telemetry: FieldTelemetry

    public var runtimeService: FieldRuntimeService? {
        radroots.runtimeService
    }

    private let lockKey = "field_ios.identity_locked"
    private var statusTask: Task<Void, Never>?
    private var telemetryProbeTask: Task<Void, Never>?
    private var secureIdentityStore: FieldSecureIdentityStore?
    private var identityMetadataStore: FieldIdentityPublicMetadataStore?
    private var captureIntake: FieldCaptureIntake?
    private var backgroundExecution: FieldBackgroundExecution?
    private let locationCheckIn = FieldLocationCheckIn.configured()
    private let externalActions = FieldExternalActions.configured()
    private let userPresenceGate = FieldUserPresenceGate.configured()
    private var lastTelemetryRelayStatus: FieldTelemetryRelayStatus?

    init(radroots: Radroots = Radroots(), telemetry: FieldTelemetry = .shared) {
        self.radroots = radroots
        self.telemetry = telemetry
        self.isLocked = UserDefaults.standard.bool(forKey: lockKey)
    }

    deinit {
        statusTask?.cancel()
        telemetryProbeTask?.cancel()
    }

    public func start() async throws {
        guard bootstrapPhase == .idle || isFailed else { return }
        telemetry.appStartupBegan()
        bootstrapPhase = .starting
        do {
            try await holdBootstrapSplashForUITestIfRequested()
            if startupFailureWasRequested {
                throw FieldAppRuntimeError.forcedStartupFailure
            }
            let service = try radroots.start(telemetry: telemetry)
            let secureStore = try FieldSecureIdentityStore.configured()
            let metadataStore = try FieldIdentityPublicMetadataStore.configured()
            #if DEBUG
            identityPolicyProbeValue = try FieldIdentityPolicyUITestProbe.value()
            #endif
            let appBundleIdentifier = try bundleIdentifier()
            let resetLocalStateRequested = BuildConfig.bool(.resetLocalState) == true
            let backgroundExecution = try FieldBackgroundExecution.configured(
                bundleIdentifier: appBundleIdentifier,
                telemetry: telemetry
            )
            self.backgroundExecution = backgroundExecution
            await FieldBackgroundURLSessionEvents.shared.attach(backgroundExecution)
            try FieldFileAccessUITestProbe.seedDestructiveResetSentinelIfRequested(
                bundleIdentifier: appBundleIdentifier,
                resetLocalStateRequested: resetLocalStateRequested
            )
            secureIdentityStore = secureStore
            identityMetadataStore = metadataStore
            if resetLocalStateRequested {
                await backgroundExecution.cancelAll()
                try FieldLocalState.resetFileRoots(bundleIdentifier: appBundleIdentifier)
                try RelaySettings.clearUserImportedRelays(bundleIdentifier: appBundleIdentifier)
                try secureStore.deleteSelectedSecret()
                metadataStore.delete()
                try await resetRuntimeIdentityState(using: service)
                applyNoIdentity()
                setLocked(false)
            } else {
                loadStoredIdentityMetadata(metadataStore)
            }
            try refreshRelaySettingsSnapshot(bundleIdentifier: appBundleIdentifier)
            let captureIntake = try FieldCaptureIntake.configured(bundleIdentifier: appBundleIdentifier)
            self.captureIntake = captureIntake
            try await backgroundExecution.start()
            await refreshBackgroundExecutionProbe(using: backgroundExecution)
            await refreshRuntimeState(using: service)
            if runtimeIdentityReady && !isLocked {
                startConnectingAndPollingStatus(using: service)
            }
            await refreshNostrProfileExternalActionCapability()
            try refreshFileAccessProbe(
                bundleIdentifier: appBundleIdentifier,
                resetLocalStateRequested: resetLocalStateRequested,
                identityResetObserved: false
            )
            try await refreshDocumentInterchangeProbe(bundleIdentifier: appBundleIdentifier)
            await refreshLocationCheckInStatus()
            await refreshCaptureIntakeState(using: captureIntake)
            bootstrapPhase = .ready
            telemetry.appStartupSucceeded(
                storedIdentityAvailable: storedIdentityAvailable,
                runtimeIdentityReady: runtimeIdentityReady,
                locked: isLocked
            )
            startTelemetryProbeRefreshForUITest()
        } catch {
            statusTask?.cancel()
            statusTask = nil
            telemetryProbeTask?.cancel()
            telemetryProbeTask = nil
            await FieldBackgroundURLSessionEvents.shared.completePendingAfterStartupFailure()
            backgroundExecution = nil
            let message = error.localizedDescription
            bootstrapPhase = .failed(message)
            telemetry.appStartupFailed(error)
            startTelemetryProbeRefreshForUITest()
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

    public func appDidBecomeActive() {
        Task {
            try? await backgroundExecution?.schedulePermittedTasks(reason: "active")
        }
    }

    public func appDidEnterBackground() {
        Task {
            _ = try? await backgroundExecution?.schedulePermittedTasks(reason: "background")
            await backgroundExecution?.performMaintenance(reason: "background")
        }
    }

    public func continueWithLocalIdentity() async throws {
        let service = try requireRuntimeService()
        do {
            try await requireUserPresence(for: .unlockIdentity)
            try await restoreStoredIdentity(using: service)
            setLocked(false)
            await refreshRuntimeState(using: service)
            await refreshNostrProfileExternalActionCapability()
            startConnectingAndPollingStatus(using: service)
            telemetry.identityCustody(action: "unlock", outcome: "success")
        } catch {
            telemetry.identityCustody(action: "unlock", outcome: FieldTelemetry.userPresenceOutcome(for: error))
            throw error
        }
    }

    public func createLocalIdentity() async throws {
        let service = try requireRuntimeService()
        do {
            try await requireUserPresence(for: .saveIdentity)
            try await createHostCustodyIdentity(using: service)
            setLocked(false)
            await refreshRuntimeState(using: service)
            await refreshNostrProfileExternalActionCapability()
            startConnectingAndPollingStatus(using: service)
            telemetry.identityCustody(action: "create", outcome: "success")
        } catch {
            telemetry.identityCustody(action: "create", outcome: FieldTelemetry.userPresenceOutcome(for: error))
            throw error
        }
    }

    public func importNostrSecret(_ secretKey: String) async throws {
        let trimmed = secretKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let service = try requireRuntimeService()
        do {
            try await requireUserPresence(for: .saveIdentity)
            let record = try await secureIdentityStoreOrConfigured().importSecret(
                trimmed,
                label: "Imported Field Identity",
                using: service
            )
            try persistIdentity(record)
            setLocked(false)
            await refreshRuntimeState(using: service)
            await refreshNostrProfileExternalActionCapability()
            startConnectingAndPollingStatus(using: service)
            telemetry.identityCustody(action: "import", outcome: "success")
        } catch {
            telemetry.identityCustody(action: "import", outcome: FieldTelemetry.userPresenceOutcome(for: error))
            throw error
        }
    }

    public func signOut() {
        telemetry.identityCustody(action: "lock", outcome: "success")
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
        do {
            try await requireUserPresence(for: .deleteIdentity)
            await backgroundExecution?.updateRuntimeState(service: service, identityUnlocked: false)
            await backgroundExecution?.cancelAll()
            try secureIdentityStoreOrConfigured().deleteSelectedSecret()
            try identityMetadataStoreOrConfigured().delete()
            try await resetRuntimeIdentityState(using: service)
            applyNoIdentity()
            setLocked(false)
            relayConnectedCount = 0
            relayConnectingCount = 0
            relayLight = .red
            relayLastError = nil
            canOpenNostrProfile = false
            externalActionStatus = nil
            await refreshRuntimeState(using: service)
            try refreshFileAccessProbe(
                bundleIdentifier: try bundleIdentifier(),
                resetLocalStateRequested: false,
                identityResetObserved: true
            )
            statusTask?.cancel()
            statusTask = nil
            telemetry.identityCustody(action: "delete", outcome: "success")
        } catch {
            telemetry.identityCustody(action: "delete", outcome: FieldTelemetry.userPresenceOutcome(for: error))
            throw error
        }
    }

    public func requireRuntimeService() throws -> FieldRuntimeService {
        guard let service = runtimeService else {
            throw FieldAppRuntimeError.runtimeNotReady
        }
        return service
    }

    public func refreshLocationCheckInStatus() async {
        switch locationCheckInState {
        case .idle:
            break
        case .checking, .checkedIn, .failed:
            return
        }
        let refreshedState = await locationCheckIn.status()
        switch locationCheckInState {
        case .idle:
            locationCheckInState = refreshedState
        case .checking, .checkedIn, .failed:
            return
        }
    }

    public func performLocationCheckIn() async {
        let currentState = await locationCheckIn.status()
        if let availability = currentState.availability {
            locationCheckInState = .checking(availability)
        }
        locationCheckInState = await locationCheckIn.checkIn()
    }

    public func refreshCaptureIntakeState() async {
        guard let captureIntake else {
            captureIntakeState.lastError = FieldCaptureIntakeError.serviceNotReady.localizedDescription
            captureIntakeState.recoveryAction = nil
            return
        }
        await refreshCaptureIntakeState(using: captureIntake)
    }

    public func importPhotoEvidence() async {
        await performCaptureIntakeOperation(.importingPhoto) { captureIntake, records in
            try await captureIntake.importPhoto(records: records)
        }
    }

    public func capturePhotoEvidence() async {
        await performCaptureIntakeOperation(.capturingPhoto) { captureIntake, records in
            try await captureIntake.capturePhoto(records: records)
        }
    }

    public func scanDocumentEvidence() async {
        await performCaptureIntakeOperation(.scanningDocument) { captureIntake, records in
            try await captureIntake.scanDocument(records: records)
        }
    }

    public func refreshNostrProfileExternalActionCapability() async {
        guard let npub else {
            canOpenNostrProfile = false
            return
        }
        canOpenNostrProfile = await externalActions.canOpenPublicNostrProfile(npub: npub)
    }

    public func openAppSettingsRecovery() async {
        await requestExternalAction {
            try await externalActions.openAppSettings()
        }
    }

    public func openCurrentNostrProfile() async {
        guard let npub else {
            externalActionStatus = "No public Nostr identity is selected."
            canOpenNostrProfile = false
            return
        }
        await requestExternalAction {
            try await externalActions.openPublicNostrProfile(npub: npub)
        }
    }

    func prepareDiagnosticsDocumentExport() throws -> RadrootsPreparedExportDocument {
        do {
            let relays = try effectiveRelaySettings().relays
            let document = try documentInterchange().prepareDiagnosticsExport(
                infoJSONString: infoJSONString,
                relays: relays,
                connectedCount: relayConnectedCount,
                connectingCount: relayConnectingCount,
                lastError: relayLastError
            )
            telemetry.documentInterchange(operation: "diagnostics_export", outcome: "success", relayCount: relays.count)
            return document
        } catch {
            telemetry.documentInterchange(
                operation: "diagnostics_export",
                outcome: FieldTelemetry.documentInterchangeOutcome(for: error)
            )
            throw error
        }
    }

    func prepareRelayConfigDocumentExport() throws -> RadrootsPreparedExportDocument {
        do {
            let relays = try effectiveRelaySettings().relays
            let document = try documentInterchange().prepareRelayConfigExport(relays: relays)
            telemetry.documentInterchange(operation: "relay_config_export", outcome: "success", relayCount: relays.count)
            return document
        } catch {
            telemetry.documentInterchange(
                operation: "relay_config_export",
                outcome: FieldTelemetry.documentInterchangeOutcome(for: error)
            )
            throw error
        }
    }

    func importedRelayConfig(from importedDocument: RadrootsImportedDocument) throws -> [String] {
        do {
            let relays = try documentInterchange().importedRelayConfig(from: importedDocument)
            telemetry.documentInterchange(operation: "relay_config_import", outcome: "success", relayCount: relays.count)
            return relays
        } catch {
            telemetry.documentInterchange(
                operation: "relay_config_import",
                outcome: FieldTelemetry.documentInterchangeOutcome(for: error)
            )
            throw error
        }
    }

    func applyImportedRelayConfig(from importedDocument: RadrootsImportedDocument) async throws -> [String] {
        do {
            let relays = try documentInterchange().importedRelayConfig(from: importedDocument)
            let snapshot = try RelaySettings.storeUserImportedRelays(
                relays,
                bundleIdentifier: bundleIdentifier()
            )
            apply(relaySettings: snapshot)
            if let service = runtimeService, runtimeIdentityReady && !isLocked {
                relayConnectedCount = 0
                relayConnectingCount = 0
                relayLight = .yellow
                relayLastError = nil
                try await service.nostrSetDefaultRelays(snapshot.relays)
                try await service.nostrConnectIfKeyPresent()
                await refreshRelayStatus(using: service)
                await backgroundExecution?.updateRuntimeState(
                    service: service,
                    identityUnlocked: true
                )
            }
            telemetry.documentInterchange(operation: "relay_config_import", outcome: "success", relayCount: relays.count)
            return snapshot.relays
        } catch {
            telemetry.documentInterchange(
                operation: "relay_config_import",
                outcome: FieldTelemetry.documentInterchangeOutcome(for: error)
            )
            throw error
        }
    }

    func publicPostShareRequest(content: String) throws -> RadrootsShareRequest {
        do {
            let request = try documentInterchange().publicPostShareRequest(content: content)
            telemetry.documentInterchange(operation: "public_share_prepare", outcome: "success")
            return request
        } catch {
            telemetry.documentInterchange(
                operation: "public_share_prepare",
                outcome: FieldTelemetry.documentInterchangeOutcome(for: error)
            )
            throw error
        }
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

    private func refreshRelaySettingsSnapshot(bundleIdentifier: String) throws {
        apply(relaySettings: try RelaySettings.effectiveSnapshot(bundleIdentifier: bundleIdentifier))
    }

    private func effectiveRelaySettings() throws -> RelaySettingsSnapshot {
        let snapshot = try RelaySettings.effectiveSnapshot(bundleIdentifier: bundleIdentifier())
        apply(relaySettings: snapshot)
        return snapshot
    }

    private func apply(relaySettings snapshot: RelaySettingsSnapshot) {
        configuredRelayURLs = snapshot.relays
        relaySettingsSourceLabel = snapshot.source.displayName
    }

    private func refreshCaptureIntakeState(using captureIntake: FieldCaptureIntake) async {
        captureIntakeState.operation = .refreshing
        captureIntakeState.lastError = nil
        captureIntakeState.recoveryAction = nil
        do {
            captureIntakeState.records = try captureIntake.loadRecords()
            captureIntakeState.support = try await captureIntake.support()
            captureIntakeState.operation = .idle
            telemetry.captureSupportRefreshed(
                support: captureIntakeState.support,
                recordCount: captureIntakeState.records.count,
                outcome: "success"
            )
        } catch {
            captureIntakeState.support = .unavailable
            captureIntakeState.operation = .idle
            captureIntakeState.lastError = error.localizedDescription
            captureIntakeState.recoveryAction = nil
            telemetry.captureSupportRefreshed(
                support: captureIntakeState.support,
                recordCount: captureIntakeState.records.count,
                outcome: FieldTelemetry.captureOutcome(for: error)
            )
        }
    }

    private func performCaptureIntakeOperation(
        _ operation: FieldCaptureIntakeOperation,
        action: (FieldCaptureIntake, [FieldCaptureRecord]) async throws -> [FieldCaptureRecord]
    ) async {
        guard let captureIntake else {
            captureIntakeState.lastError = FieldCaptureIntakeError.serviceNotReady.localizedDescription
            return
        }
        captureIntakeState.operation = operation
        captureIntakeState.lastError = nil
        captureIntakeState.recoveryAction = nil
        do {
            let updatedRecords = try await action(captureIntake, captureIntakeState.records)
            captureIntakeState.records = updatedRecords
            captureIntakeState.support = try await captureIntake.support()
            captureIntakeState.operation = .idle
            captureIntakeState.recoveryAction = nil
            telemetry.captureOperation(
                operation: operation,
                outcome: "success",
                recordCount: captureIntakeState.records.count,
                recoveryAction: nil
            )
        } catch {
            captureIntakeState.operation = .idle
            captureIntakeState.lastError = error.localizedDescription
            captureIntakeState.recoveryAction = captureRecoveryAction(for: error)
            telemetry.captureOperation(
                operation: operation,
                outcome: FieldTelemetry.captureOutcome(for: error),
                recordCount: captureIntakeState.records.count,
                recoveryAction: captureIntakeState.recoveryAction
            )
        }
    }

    private func captureRecoveryAction(for error: Error) -> FieldExternalActionRecovery? {
        guard let captureError = error as? RadrootsCaptureIntakeError else {
            return nil
        }
        switch captureError {
        case .permissionDenied:
            return .appSettings
        case .invalidRequest, .unavailable, .userCancelled, .transientFailure, .permanentFailure:
            return nil
        }
    }

    private var isFailed: Bool {
        if case .failed = bootstrapPhase {
            return true
        }
        return false
    }

    private var uiTestWasRequested: Bool {
        #if DEBUG
        return FieldUITestHarness.isRequested
        #else
        return false
        #endif
    }

    private var uiTestBootstrapSplashHoldNanoseconds: UInt64? {
        #if DEBUG
        guard uiTestWasRequested else { return nil }
        guard let raw = FieldUITestHarness.string("RADROOTS_FIELD_IOS_UI_TEST_BOOTSTRAP_SPLASH_HOLD_SECONDS"),
              let seconds = Double(raw),
              seconds.isFinite,
              seconds > 0 else {
            return nil
        }
        return UInt64(seconds * 1_000_000_000)
        #else
        return nil
        #endif
    }

    private func holdBootstrapSplashForUITestIfRequested() async throws {
        guard let nanoseconds = uiTestBootstrapSplashHoldNanoseconds else { return }
        try await Task.sleep(nanoseconds: nanoseconds)
    }

    private var startupFailureWasRequested: Bool {
        #if DEBUG
        guard uiTestWasRequested else {
            return false
        }
        let arguments = ProcessInfo.processInfo.arguments
        if BuildConfig.string(.runtimeMode) == "ui-test-startup-failure" {
            return true
        }
        if FieldUITestHarness.bool("RADROOTS_FIELD_IOS_FORCE_STARTUP_FAILURE", default: false) {
            return true
        }
        return arguments.contains("--radroots-field-ios-force-startup-failure")
        #else
        return false
        #endif
    }

    private func configureRelays(using service: FieldRuntimeService) async throws {
        try await service.nostrSetDefaultRelays(try effectiveRelaySettings().relays)
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
        await backgroundExecution?.updateRuntimeState(
            service: service,
            identityUnlocked: runtimeIdentityReady && !isLocked
        )
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
        let telemetryStatus = FieldTelemetryRelayStatus(
            connectedCount: relayConnectedCount,
            connectingCount: relayConnectingCount,
            configuredRelayCount: configuredRelayURLs.count,
            light: relayLight.telemetryValue
        )
        if telemetryStatus != lastTelemetryRelayStatus {
            lastTelemetryRelayStatus = telemetryStatus
            telemetry.relayStatusChanged(
                connectedCount: telemetryStatus.connectedCount,
                connectingCount: telemetryStatus.connectingCount,
                configuredRelayCount: telemetryStatus.configuredRelayCount,
                light: telemetryStatus.light
            )
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
            canOpenNostrProfile = false
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

    private func requireUserPresence(for action: FieldUserPresenceAction) async throws {
        do {
            let record = try await userPresenceGate.requirePresence(for: action)
            userPresenceStatus = record.statusText
            telemetry.userPresence(action: action, outcome: "success")
        } catch {
            userPresenceStatus = error.localizedDescription
            telemetry.userPresence(action: action, outcome: FieldTelemetry.userPresenceOutcome(for: error))
            throw error
        }
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
        await backgroundExecution?.updateRuntimeState(service: service, identityUnlocked: false)
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
        canOpenNostrProfile = false
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

    private func refreshDocumentInterchangeProbe(bundleIdentifier: String) async throws {
        documentInterchangeProbeValue = try FieldDocumentInterchangeUITestProbe.startupValue(
            bundleIdentifier: bundleIdentifier,
            infoJSONString: infoJSONString,
            relays: effectiveRelaySettings().relays,
            connectedCount: relayConnectedCount,
            connectingCount: relayConnectingCount,
            lastError: relayLastError
        )
        guard FieldDocumentInterchangeUITestProbe.isRequested else {
            return
        }
        let diagnosticsExport = try prepareDiagnosticsDocumentExport()
        releasePreparedDocumentExport(diagnosticsExport)
        let relayConfigExport = try prepareRelayConfigDocumentExport()
        releasePreparedDocumentExport(relayConfigExport)
        if let relayImportDocument = try FieldDocumentInterchangeUITestProbe.relayImportDocument(
            bundleIdentifier: bundleIdentifier
        ) {
            let importedRelays = try await applyImportedRelayConfig(from: relayImportDocument)
            documentInterchangeProbeValue = [
                documentInterchangeProbeValue,
                "relay_import_applied=true",
                "relay_settings_source=\(relaySettingsSourceLabel)",
                "relay_settings_count=\(importedRelays.count)",
                "relay_settings_contains_production=\(importedRelays.contains("wss://radroots.org"))"
            ].compactMap { $0 }.joined(separator: ";")
        }
        _ = try publicPostShareRequest(content: "  public field update  ")
    }

    private func requestExternalAction(
        _ action: () async throws -> FieldExternalActionRequestRecord
    ) async {
        do {
            let record = try await action()
            externalActionStatus = record.statusText
            telemetry.externalAction(operation: "open", kind: record.kind, outcome: "success")
        } catch {
            externalActionStatus = error.localizedDescription
            telemetry.externalAction(
                operation: "open",
                kind: nil,
                outcome: FieldTelemetry.externalActionOutcome(for: error)
            )
        }
    }

    private func setLocked(_ value: Bool) {
        isLocked = value
        UserDefaults.standard.set(value, forKey: lockKey)
    }

    private func startConnectingAndPollingStatus(using service: FieldRuntimeService) {
        statusTask?.cancel()
        statusTask = Task { [weak self] in
            do {
                try await self?.connect(using: service)
            } catch {
                self?.relayLastError = error.localizedDescription
                self?.relayLight = .red
            }
            while !Task.isCancelled {
                await self?.refreshRuntimeState(using: service)
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
    }

    private func startTelemetryProbeRefreshForUITest() {
        guard FieldTelemetryUITestProbe.isRequested else {
            return
        }
        telemetryProbeTask?.cancel()
        telemetryProbeTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refreshTelemetryProbeValue()
                try? await Task.sleep(nanoseconds: 250_000_000)
            }
        }
    }

    private func refreshTelemetryProbeValue() async {
        telemetryProbeValue = await FieldTelemetryUITestProbe.value(recordedBy: telemetry)
    }

    private func refreshBackgroundExecutionProbe(using backgroundExecution: FieldBackgroundExecution) async {
        backgroundExecutionProbeValue = await backgroundExecution.uiTestProbeValue()
    }

    private func shortNpub(_ value: String) -> String {
        guard value.count > 18 else { return value }
        return "\(value.prefix(12))...\(value.suffix(6))"
    }
}

private struct FieldTelemetryRelayStatus: Equatable {
    let connectedCount: UInt32
    let connectingCount: UInt32
    let configuredRelayCount: Int
    let light: String
}

private extension AppState.RelayLight {
    var telemetryValue: String {
        switch self {
        case .red:
            "red"
        case .yellow:
            "yellow"
        case .green:
            "green"
        }
    }
}
