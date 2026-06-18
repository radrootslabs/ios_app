import Foundation
import RadrootsKit

enum FieldUserPresenceAction: Equatable, Sendable {
    case unlockIdentity
    case saveIdentity
    case deleteIdentity

    var reason: String {
        switch self {
        case .unlockIdentity:
            "Unlock your local Nostr identity."
        case .saveIdentity:
            "Save your local Nostr identity on this iPhone."
        case .deleteIdentity:
            "Delete your local Nostr identity from this iPhone."
        }
    }

    var verifiedStatusText: String {
        switch self {
        case .unlockIdentity:
            "Verified user presence to unlock identity."
        case .saveIdentity:
            "Verified user presence to save identity."
        case .deleteIdentity:
            "Verified user presence to delete identity."
        }
    }
}

struct FieldUserPresenceRequestRecord: Equatable, Sendable {
    let action: FieldUserPresenceAction
    let statusText: String
}

enum FieldUserPresenceGateError: LocalizedError, Equatable {
    case notVerified

    var errorDescription: String? {
        switch self {
        case .notVerified:
            "User presence was not verified."
        }
    }
}

final class FieldUserPresenceGate: Sendable {
    private let userPresence: any RadrootsUserPresence

    init(userPresence: any RadrootsUserPresence) {
        self.userPresence = userPresence
    }

    static func configured() -> FieldUserPresenceGate {
        #if DEBUG
        if FieldUITestHarness.isRequested {
            return FieldUserPresenceGate(userPresence: uiTestUserPresence())
        }
        #endif
        return FieldUserPresenceGate(userPresence: RadrootsAppleUserPresence())
    }

    func requirePresence(for action: FieldUserPresenceAction) async throws -> FieldUserPresenceRequestRecord {
        let request = try RadrootsUserPresenceRequest(reason: action.reason)
        let result = try await userPresence.verify(request)
        guard result.verified else {
            throw FieldUserPresenceGateError.notVerified
        }
        return FieldUserPresenceRequestRecord(action: action, statusText: action.verifiedStatusText)
    }

    #if DEBUG
    private static func uiTestUserPresence() -> any RadrootsUserPresence {
        let outcomes = uiTestOutcomes()
        let status = uiTestStatus()
        return FieldUITestUserPresence(status: status, outcomes: outcomes.map(\.result))
    }

    private static func uiTestStatus() -> RadrootsUserPresenceStatus {
        let raw = FieldUITestHarness.string("RADROOTS_FIELD_IOS_UI_TEST_USER_PRESENCE_STATUS")?.lowercased()
        switch raw {
        case "unavailable":
            return .unavailable
        case "device_credential":
            return RadrootsUserPresenceStatus(
                support: .deviceCredential,
                biometryKind: .none,
                canEvaluateDeviceCredential: true,
                canEvaluateBiometrics: false
            )
        case nil, "", "available", "biometrics":
            return RadrootsUserPresenceStatus(
                support: .biometricsOrDeviceCredential,
                biometryKind: .faceID,
                canEvaluateDeviceCredential: true,
                canEvaluateBiometrics: true
            )
        default:
            return .unavailable
        }
    }

    private static func uiTestOutcomes() -> [FieldUserPresenceUITestOutcome] {
        let raw = FieldUITestHarness.string("RADROOTS_FIELD_IOS_UI_TEST_USER_PRESENCE_OUTCOME") ?? ""
        let parts = raw
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
        if parts.isEmpty {
            return [.success]
        }
        return parts.map { FieldUserPresenceUITestOutcome(rawValue: $0) ?? .denied }
    }
    #endif
}

#if DEBUG
private enum FieldUserPresenceUITestOutcome: String {
    case success
    case unverified
    case cancelled
    case denied
    case unavailable
    case timeout
    case transientFailure = "transient_failure"
    case permanentFailure = "permanent_failure"

    var result: Result<Bool, RadrootsUserPresenceError> {
        switch self {
        case .success:
            .success(true)
        case .unverified:
            .success(false)
        case .cancelled:
            .failure(.userCancelled("User presence was cancelled."))
        case .denied:
            .failure(.permissionDenied("User presence permission is denied."))
        case .unavailable:
            .failure(.unavailable("User presence is unavailable."))
        case .timeout:
            .failure(.timeout("User presence timed out."))
        case .transientFailure:
            .failure(.transientFailure("User presence failed. Please retry."))
        case .permanentFailure:
            .failure(.permanentFailure("User presence failed."))
        }
    }
}
#endif
