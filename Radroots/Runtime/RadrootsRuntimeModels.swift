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
    let blossomOrigins: [String]
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
            && lhs.blossomOrigins == rhs.blossomOrigins
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
    let crateName: String
    let crateVersion: String
    let isClosed: Bool
}

enum RadrootsRuntimeChangeKind: Sendable, Equatable {
    case initial
    case identity
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
             let .shutdown(failure):
            failure.safeMessage
        }
    }
}

enum RadrootsRuntimeLifecycle: Sendable, Equatable {
    case stopped
    case starting(generation: UInt64)
    case running(generation: UInt64)
    case stopping(generation: UInt64)
    case failed(generation: UInt64, failure: RadrootsRuntimeFailure)
}
