import Foundation

enum RadrootsProtectedDataState: Sendable, Equatable {
    case available
    case unavailable
}

enum RadrootsRuntimeNetworkProfile: Sendable, Equatable {
    case publicNetwork
    case simulator
    case device
}

enum RadrootsBlossomHostKind: String, Codable, Sendable, Equatable {
    case native
    case simulator
    case physicalDevice = "physical_device"
}

enum RadrootsBlossomEndpointAuthority: String, Codable, Sendable, Equatable {
    case publicWebPKI = "public_web_pki"
    case loopbackDevelopment = "loopback_development"
    case privateNetworkDevelopment = "private_network_development"

    init?(runtimeValue: String) {
        switch runtimeValue {
        case "public_webpki": self = .publicWebPKI
        case "loopback_development": self = .loopbackDevelopment
        case "private_network_development": self = .privateNetworkDevelopment
        default: return nil
        }
    }
}

struct RadrootsBlossomEndpointConfiguration: Codable, Sendable, Equatable {
    let hostKind: RadrootsBlossomHostKind
    let endpointAuthority: RadrootsBlossomEndpointAuthority
    let primaryOrigin: String
    let fallbackOrigins: [String]
}

struct RadrootsBlossomConfigurationStatus: Sendable, Equatable {
    let schemaVersion: UInt16
    let hostKind: String
    let endpointAuthority: String
    let primaryOrigin: String
    let fallbackOrigins: [String]
    let configFingerprint: String
}

struct RadrootsBlossomEvidence: Sendable, Equatable {
    let schemaVersion: UInt16
    let origin: String
    let configFingerprint: String
    let state: String
    let lastSuccessfulState: String
    let transportSecurity: String
    let observedAtUnixMilliseconds: UInt64?
    let httpStatus: UInt16?
    let errorCode: String?
    let serverErrorCode: String?
    let errorPhase: String?
    let retryable: Bool
    let possibleOrphan: Bool
    let attempts: UInt8
}

struct RadrootsRuntimeAppMetadata: Sendable, Equatable {
    let bundleIdentifier: String
    let version: String
    let buildNumber: String
    let buildSHA: String?
}

enum RadrootsRuntimeSignerAvailability: Sendable, Equatable {
    case ready
    case busy
    case locked
    case unavailable
}

enum RadrootsRuntimeSigningPurpose: Sendable, Equatable {
    case nostrEvent
    case blossomUpload
}

struct RadrootsRuntimeSigningRequest: Sendable, Equatable {
    let operationID: String
    let signerRequestID: String
    let publicKeyHex: String
    let purpose: RadrootsRuntimeSigningPurpose
    let deadlineUnixMilliseconds: UInt64
    let digest: Data
}

enum RadrootsRuntimeSigningOutcome: Sendable, Equatable {
    case signed(signatureHex: String)
    case locked
    case cancelled
    case rejected
    case timedOut
    case unavailable
    case invalidated
    case failed
}

protocol RadrootsRuntimeSigner: Sendable {
    func availability() async -> RadrootsRuntimeSignerAvailability
    func sign(_ request: RadrootsRuntimeSigningRequest) async -> RadrootsRuntimeSigningOutcome
}

struct RadrootsRuntimeLaunchConfiguration: Sendable {
    let applicationSupportDirectory: String
    let publicKeyHex: String
    let sourceGenerationHex: String
    let sourceGenerationCreatedAtUnixMilliseconds: UInt64
    let protectedData: RadrootsProtectedDataState
    let networkProfile: RadrootsRuntimeNetworkProfile
    let writableRelays: [String]
    let blossom: RadrootsBlossomEndpointConfiguration?
    let app: RadrootsRuntimeAppMetadata
    let signerGeneration: String
    let signer: any RadrootsRuntimeSigner
}

extension RadrootsRuntimeLaunchConfiguration: Equatable {
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.applicationSupportDirectory == rhs.applicationSupportDirectory
            && lhs.publicKeyHex == rhs.publicKeyHex
            && lhs.sourceGenerationHex == rhs.sourceGenerationHex
            && lhs.sourceGenerationCreatedAtUnixMilliseconds
            == rhs.sourceGenerationCreatedAtUnixMilliseconds
            && lhs.protectedData == rhs.protectedData
            && lhs.networkProfile == rhs.networkProfile
            && lhs.writableRelays == rhs.writableRelays
            && lhs.blossom == rhs.blossom
            && lhs.app == rhs.app
            && lhs.signerGeneration == rhs.signerGeneration
    }
}

struct RadrootsRuntimeIdentity: Sendable, Equatable {
    let publicKeyHex: String
    let hostSignerConfigured: Bool
}

struct RadrootsRelayEndpointStatus: Sendable, Equatable {
    let url: String
    let access: String
    let readState: String
    let writeState: String
    let readLastAttemptUnixMilliseconds: UInt64?
    let writeLastAttemptUnixMilliseconds: UInt64?
    let readNextAttemptUnixMilliseconds: UInt64?
    let writeNextAttemptUnixMilliseconds: UInt64?
}

struct RadrootsRelayStatus: Sendable, Equatable {
    let profile: String
    let state: String
    let readAvailability: String
    let writeAvailability: String
    let relays: [RadrootsRelayEndpointStatus]
}

struct RadrootsRuntimeSnapshot: Sendable, Equatable {
    let identity: RadrootsRuntimeIdentity
    let relay: RadrootsRelayStatus?
    let blossomConfiguration: RadrootsBlossomConfigurationStatus?
    let blossomEvidence: RadrootsBlossomEvidence?
    let crateName: String
    let crateVersion: String
    let isClosed: Bool
}

enum RadrootsRuntimeChangeKind: Sendable, Equatable {
    case initial
    case identity
    case settings
    case profile
    case today
    case drafts
    case relay
    case media
    case lifecycle
}

struct RadrootsRuntimeChange: Sendable, Equatable {
    let schemaVersion: UInt16
    let generation: UInt64
    let kind: RadrootsRuntimeChangeKind
    let entityID: String?
}

struct RadrootsRuntimeShutdownReceipt: Sendable, Equatable {
    let state: String
    let alreadyClosed: Bool

    static let alreadyStopped = Self(state: "closed", alreadyClosed: true)
}

enum RadrootsRuntimeOperationKind: String, Sendable, Equatable, Hashable {
    case startup
    case operation
    case reconfiguration
    case subscription
    case shutdown
}

struct RadrootsRuntimeOperationIdentity: Sendable, Equatable, Hashable {
    let generation: UInt64
    let sequence: UInt64
    let kind: RadrootsRuntimeOperationKind

    var rawValue: String {
        "ios-runtime-\(generation)-\(sequence)-\(kind.rawValue)"
    }
}

struct RadrootsRuntimeDeadlinePolicy: Sendable, Equatable {
    let startupNanoseconds: UInt64
    let operationNanoseconds: UInt64
    let subscriptionNanoseconds: UInt64
    let shutdownNanoseconds: UInt64

    init(
        startupNanoseconds: UInt64 = 30_000_000_000,
        operationNanoseconds: UInt64 = 30_000_000_000,
        subscriptionNanoseconds: UInt64 = 10_000_000_000,
        shutdownNanoseconds: UInt64 = 10_000_000_000
    ) {
        precondition(startupNanoseconds > 0 && startupNanoseconds <= 120_000_000_000)
        precondition(operationNanoseconds > 0 && operationNanoseconds <= 120_000_000_000)
        precondition(subscriptionNanoseconds > 0 && subscriptionNanoseconds <= 60_000_000_000)
        precondition(shutdownNanoseconds > 0 && shutdownNanoseconds <= 60_000_000_000)
        self.startupNanoseconds = startupNanoseconds
        self.operationNanoseconds = operationNanoseconds
        self.subscriptionNanoseconds = subscriptionNanoseconds
        self.shutdownNanoseconds = shutdownNanoseconds
    }

    static let production = Self()
}

enum RadrootsRuntimeObservationState: Sendable, Equatable {
    case inactive
    case subscribing(attempt: UInt32)
    case active
    case retrying(attempt: UInt32, message: String)
    case stopped
}

enum RadrootsRuntimeObservationBackoff {
    static func sleep(attempt: UInt32) async throws {
        let exponent = min(attempt.saturatingSubtractingOne, 7)
        let delay = min(UInt64(250_000_000) << exponent, 30_000_000_000)
        try await Task.sleep(nanoseconds: delay)
    }
}

private extension UInt32 {
    var saturatingSubtractingOne: UInt32 {
        self == 0 ? 0 : self - 1
    }
}

struct RadrootsRuntimeFailure: Error, Sendable, Equatable {
    let schemaVersion: UInt16
    let code: String
    let category: String
    let retryable: Bool
    let recoveryActions: [String]
    let operationID: String?
    let capabilityID: String?
    let safeMessage: String

    static func local(operation: String, code: String, safeMessage: String) -> Self {
        Self(
            schemaVersion: 1,
            code: code,
            category: "runtime",
            retryable: false,
            recoveryActions: [],
            operationID: operation,
            capabilityID: nil,
            safeMessage: safeMessage
        )
    }
}

extension RadrootsRuntimeFailure: LocalizedError {
    var errorDescription: String? {
        safeMessage
    }
}

enum RadrootsRuntimeClientError: Error, Sendable, Equatable {
    case invalidBufferCapacity
    case notRunning
    case superseded
    case startup(RadrootsRuntimeFailure)
    case subscription(RadrootsRuntimeFailure)
    case status(RadrootsRuntimeFailure)
    case today(RadrootsRuntimeFailure)
    case add(RadrootsRuntimeFailure)
    case support(RadrootsRuntimeFailure)
    case shutdown(RadrootsRuntimeFailure)
}

extension RadrootsRuntimeClientError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .invalidBufferCapacity:
            "The requested runtime event buffer is outside the supported range."
        case .notRunning:
            "The Radroots runtime is not running."
        case .superseded:
            "A newer runtime lifecycle request replaced this request."
        case let .startup(failure),
             let .subscription(failure),
             let .status(failure),
             let .today(failure),
             let .add(failure),
             let .support(failure),
             let .shutdown(failure):
            failure.safeMessage
        }
    }
}

struct RadrootsLocalNetwork: Sendable, Equatable, Hashable, Identifiable {
    let schemaVersion: UInt16
    let id: String
    let label: String
    let relayURLs: [String]
    let locality: String?
    let followedAuthors: [String]
    let generation: UInt64

    static func defaultContext(snapshot: RadrootsRuntimeSnapshot) -> Self {
        Self(
            schemaVersion: 1,
            id: "default",
            label: "Local network",
            relayURLs: snapshot.relay?.relays.map(\.url) ?? [],
            locality: nil,
            followedAuthors: [],
            generation: 1
        )
    }
}

enum RadrootsTodayCardType: String, CaseIterable, Sendable, Equatable, Hashable {
    case update
    case photoUpdate
    case ask
    case event
    case foodAvailability

    var label: String {
        switch self {
        case .update: "Update"
        case .photoUpdate: "Photo update"
        case .ask: "Ask"
        case .event: "Event"
        case .foodAvailability: "Food availability"
        }
    }
}

enum RadrootsMediaVerificationState: String, Sendable, Equatable, Hashable {
    case pending
    case verified
    case failed
    case unavailable
}

struct RadrootsMediaReference: Sendable, Equatable, Hashable, Identifiable {
    let url: String
    let sha256: String?
    let mediaType: String?
    let width: UInt32?
    let height: UInt32?
    let byteSize: UInt64?
    let alt: String?
    let verification: RadrootsMediaVerificationState

    var id: String {
        sha256 ?? url
    }

    var trustedURL: URL? {
        guard verification == .verified,
              let candidate = URL(string: url),
              candidate.scheme?.lowercased() == "https"
        else {
            return nil
        }
        return candidate
    }
}

struct RadrootsProfileSummary: Sendable, Equatable, Hashable {
    let authorPublicKey: String
    let name: String?
    let displayName: String?
    let about: String?
    let picture: RadrootsMediaReference?
    let banner: RadrootsMediaReference?
    let nip05: String?
    let website: String?
    let lightningAddress: String?

    var preferredName: String {
        for candidate in [displayName, name] {
            if let candidate, !candidate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return candidate
            }
        }
        guard authorPublicKey.count > 16 else { return authorPublicKey }
        return "\(authorPublicKey.prefix(8))…\(authorPublicKey.suffix(8))"
    }
}

enum RadrootsThreadEntryType: String, Sendable, Equatable, Hashable {
    case profile
    case reply
    case comment
    case deletion
}

struct RadrootsThreadEntry: Sendable, Equatable, Hashable, Identifiable {
    let id: String
    let authorPublicKey: String
    let content: String
    let authoredAtUnixSeconds: UInt64
    let type: RadrootsThreadEntryType
    let root: String
    let parentEventID: String
    let authorProfile: RadrootsProfileSummary?
}

enum RadrootsCardLifecycleState: String, Sendable, Equatable, Hashable {
    case active
    case sold
    case past
}

struct RadrootsTodayCard: Sendable, Equatable, Hashable, Identifiable {
    let id: String
    let type: RadrootsTodayCardType
    let sourceEventID: String
    let sourceAddress: String?
    let authorPublicKey: String
    let contractID: String
    let title: String?
    let content: String
    let authoredAtUnixSeconds: UInt64
    let effectiveAtUnixSeconds: UInt64
    let eventStartUnixSeconds: UInt64?
    let eventEndUnixSeconds: UInt64?
    let location: String?
    let priceAmount: String?
    let priceCurrency: String?
    let priceUnit: String?
    let quantity: String?
    let foodSummary: String?
    let foodPublishedAtUnixSeconds: UInt64?
    let foodStatus: String?
    let contextRank: UInt8
    let inclusionReason: String
    let media: [RadrootsMediaReference]
    let lifecycle: RadrootsCardLifecycleState
    let rankDigest: String?
    let authorProfile: RadrootsProfileSummary?
    let thread: [RadrootsThreadEntry]
    let localOperationID: String?
    let localOperationState: String?

    var authorName: String {
        authorProfile?.preferredName
            ?? RadrootsProfileSummary(
                authorPublicKey: authorPublicKey,
                name: nil,
                displayName: nil,
                about: nil,
                picture: nil,
                banner: nil,
                nip05: nil,
                website: nil,
                lightningAddress: nil
            ).preferredName
    }

    var priceSummary: String? {
        guard let priceAmount, let priceCurrency, let priceUnit else { return nil }
        return "\(priceAmount) \(priceCurrency)/\(priceUnit)"
    }

    var accessibilitySummary: String {
        var parts = [type.label, "by \(authorName)"]
        if let title {
            parts.append(title)
        }
        if !content.isEmpty {
            parts.append(content)
        }
        if let priceSummary {
            parts.append(priceSummary)
        }
        if lifecycle != .active {
            parts.append(lifecycle.rawValue)
        }
        if let localOperationState {
            parts.append(localOperationState)
        }
        return parts.joined(separator: ", ")
    }
}

struct RadrootsTodayPageRequest: Sendable, Equatable {
    let context: RadrootsLocalNetwork
    let limit: UInt16
    let asOfUnixSeconds: UInt64?
    let cursor: String?

    static func first(
        context: RadrootsLocalNetwork,
        limit: UInt16,
        asOfUnixSeconds: UInt64
    ) -> Self {
        Self(context: context, limit: limit, asOfUnixSeconds: asOfUnixSeconds, cursor: nil)
    }

    static func after(context: RadrootsLocalNetwork, limit: UInt16, cursor: String) -> Self {
        Self(context: context, limit: limit, asOfUnixSeconds: nil, cursor: cursor)
    }
}

struct RadrootsTodayPage: Sendable, Equatable {
    let asOfUnixSeconds: UInt64
    let items: [RadrootsTodayCard]
    let nextCursor: String?
}

enum RadrootsTodayProjectionUpdate: Sendable, Equatable {
    case incremental
    case rebuild
}

struct RadrootsTodayRefreshReceipt: Sendable, Equatable {
    let update: RadrootsTodayProjectionUpdate
    let sourceEvents: UInt64
    let visibleCards: UInt64
    let profiles: UInt64
    let threadEntries: UInt64
    let contentGeneration: UInt64
    let changed: Bool
}

enum RadrootsSearchResultType: Sendable, Equatable, Hashable {
    case card
    case profile
}

struct RadrootsSearchResult: Sendable, Equatable, Hashable, Identifiable {
    let type: RadrootsSearchResultType
    let id: String
    let card: RadrootsTodayCard?
    let profile: RadrootsProfileSummary?
}

struct RadrootsMeSnapshot: Sendable, Equatable {
    let publicKey: String
    let profile: RadrootsProfileSummary?
    let cards: [RadrootsTodayCard]
}

enum RadrootsAddCommandType: String, CaseIterable, Sendable, Equatable, Hashable, Identifiable {
    case createUpdate
    case createPhotoUpdate
    case createAsk
    case createEvent
    case createFoodAvailability

    var id: String {
        rawValue
    }

    var label: String {
        switch self {
        case .createUpdate: "Update"
        case .createPhotoUpdate: "Photo update"
        case .createAsk: "Ask"
        case .createEvent: "Event"
        case .createFoodAvailability: "Food availability"
        }
    }

    var todayCardType: RadrootsTodayCardType {
        switch self {
        case .createUpdate: .update
        case .createPhotoUpdate: .photoUpdate
        case .createAsk: .ask
        case .createEvent: .event
        case .createFoodAvailability: .foodAvailability
        }
    }

    var acceptsMedia: Bool {
        self != .createUpdate
    }

    var requiresMedia: Bool {
        self == .createPhotoUpdate
    }
}

enum RadrootsAddFieldKind: Sendable, Equatable, Hashable {
    case text
    case multilineText
    case date
    case dateTime
    case decimal
    case choice
    case location
    case media
}

struct RadrootsAddField: Sendable, Equatable, Hashable, Identifiable {
    let schemaVersion: UInt16
    let id: String
    let label: String
    let kind: RadrootsAddFieldKind
    let required: Bool
    let choices: [String]
    let maxBytes: UInt64?
}

struct RadrootsAddSchema: Sendable, Equatable, Hashable, Identifiable {
    let schemaVersion: UInt16
    let commandType: RadrootsAddCommandType
    let label: String
    let fields: [RadrootsAddField]

    var id: RadrootsAddCommandType {
        commandType
    }
}

enum RadrootsEventTiming: String, Sendable, Equatable, Hashable, CaseIterable, Identifiable {
    case allDay
    case timed

    var id: String {
        rawValue
    }

    var label: String {
        self == .allDay ? "All day" : "Specific time"
    }
}

struct RadrootsPreparedMedia: Sendable, Equatable, Hashable, Identifiable {
    let opaqueReference: String
    let remoteURL: String?
    let sha256: String
    let mediaType: String
    let byteSize: UInt64
    let width: UInt32
    let height: UInt32
    var alt: String
    let preparedAtUnixSeconds: UInt64

    var id: String {
        opaqueReference
    }
}

struct RadrootsPreparedMediaHandle: Sendable, Equatable {
    let media: RadrootsPreparedMedia
    let fileDescriptor: UInt64
}

struct RadrootsAddForm: Sendable, Equatable, Hashable {
    var commandType: RadrootsAddCommandType
    var content: String = ""
    var identifier: String?
    var title: String?
    var summary: String?
    var location: String?
    var eventTiming: RadrootsEventTiming?
    var eventStartDate: String?
    var eventEndDate: String?
    var eventStartUnixSeconds: UInt64?
    var eventEndUnixSeconds: UInt64?
    var eventTimezone: String?
    var priceAmount: String?
    var currency: String?
    var unit: String?
    var quantity: String?
    var foodPublishedAtUnixSeconds: UInt64?
    var foodStatus: String?
    var media: [RadrootsPreparedMedia] = []

    static func empty(_ type: RadrootsAddCommandType = .createUpdate) -> Self {
        var form = Self(commandType: type)
        if type == .createEvent {
            form.eventTiming = .timed
            form.eventTimezone = TimeZone.current.identifier
        }
        return form
    }
}

struct RadrootsAddRuntimeInput: Sendable, Equatable {
    let form: RadrootsAddForm
    let media: [RadrootsPreparedMediaHandle]
}

enum RadrootsDraftKind: String, Sendable, Equatable, Hashable {
    case add
    case retraction
}

enum RadrootsOutboxState: String, Sendable, Equatable, Hashable {
    case draft
    case mediaPreparing
    case mediaUploading
    case readyToSign
    case signing
    case signed
    case queued
    case delivering
    case partiallyDelivered
    case retryable
    case terminal
    case cancelled
    case complete

    var isEditable: Bool {
        self == .draft || self == .mediaPreparing
    }

    var canAdvance: Bool {
        self == .queued || self == .retryable || self == .partiallyDelivered
    }

    var canCancel: Bool {
        ![.cancelled, .complete, .terminal].contains(self)
    }

    var label: String {
        rawValue
            .replacingOccurrences(of: "([a-z])([A-Z])", with: "$1 $2", options: .regularExpression)
            .capitalized
    }
}

enum RadrootsDraftMediaStage: String, Sendable, Equatable, Hashable {
    case pending
    case preparing
    case uploading
    case verified
    case failed
    case orphaned
}

struct RadrootsDraftMediaStatus: Sendable, Equatable, Hashable {
    let url: String
    let stage: RadrootsDraftMediaStage
    let uploadAttempts: UInt8
    let verifiedAtUnixMilliseconds: UInt64?
    let possibleOrphan: Bool
    let orphanReasonCode: String?
    let orphanRecordedAtUnixMilliseconds: UInt64?
}

struct RadrootsOperationSettlement: Sendable, Equatable, Hashable {
    let artifacts: UInt16
    let signed: UInt16
    let admitted: UInt16
    let pending: UInt16
    let retryable: UInt16
    let indeterminate: UInt16
    let failedTerminal: UInt16
    let cancelled: UInt16
    let deliveryPlans: UInt16
    let deliverySatisfied: UInt16
    let deliveryPending: UInt16
    let deliveryRetryable: UInt16
    let deliveryExhausted: UInt16
    let deliveryFailedTerminal: UInt16
    let deliveryCancelled: UInt16

    var summary: String {
        if deliverySatisfied > 0 {
            return "Delivered"
        }
        if deliveryRetryable > 0 || retryable > 0 {
            return "Saved; delivery can be retried"
        }
        if indeterminate > 0 {
            return "Delivery outcome is not yet known"
        }
        if failedTerminal > 0 || deliveryFailedTerminal > 0 {
            return "Delivery failed"
        }
        if admitted > 0 {
            return "Published locally; relay delivery is pending"
        }
        if signed > 0 {
            return "Signed; local publication is pending"
        }
        return "Waiting"
    }
}

struct RadrootsDraftStatus: Sendable, Equatable, Hashable, Identifiable {
    let id: String
    let revision: UInt64
    let authorPublicKey: String
    let kind: RadrootsDraftKind
    let commandType: RadrootsAddCommandType
    let form: RadrootsAddForm?
    let state: RadrootsOutboxState
    let cardID: String
    let operationID: String?
    let createdAtUnixMilliseconds: UInt64
    let updatedAtUnixMilliseconds: UInt64
    let media: [RadrootsDraftMediaStatus]
    let settlement: RadrootsOperationSettlement?

    var honestSummary: String {
        settlement?.summary ?? state.label
    }
}

struct RadrootsRetractionDraftInput: Sendable, Equatable, Hashable {
    let commandType: RadrootsAddCommandType
    let targetCardID: String
    let targetEventID: String
    let targetKind: UInt32
    let targetAddress: String?
    let reason: String
}

struct RadrootsBlossomUploadIntent: Sendable, Equatable {
    let draftID: String
    let expectedRevision: UInt64
    let media: RadrootsPreparedMediaHandle
}

enum RadrootsRuntimeLifecycle: Sendable, Equatable {
    case stopped
    case starting(generation: UInt64)
    case running(generation: UInt64)
    case stopping(generation: UInt64)
    case failed(generation: UInt64, failure: RadrootsRuntimeFailure)
}
