import Foundation
import RadrootsKit

public enum FieldExternalActionRecovery: String, Equatable, Sendable {
    case appSettings
}

public struct FieldExternalActionRequestRecord: Equatable, Sendable {
    public let kind: RadrootsExternalActionDestinationKind
    public let urlString: String?

    init(destination: RadrootsExternalActionDestination) {
        self.kind = destination.kind
        self.urlString = destination.url?.absoluteString
    }

    public var statusText: String {
        switch kind {
        case .appSettings:
            "Requested app settings"
        case .web:
            "Requested web link"
        case .nostr:
            "Requested Nostr profile"
        case .appleMaps:
            "Requested Apple Maps"
        }
    }
}

final class FieldExternalActions: Sendable {
    private let actions: any RadrootsExternalActions

    init(actions: any RadrootsExternalActions) {
        self.actions = actions
    }

    static func configured() -> FieldExternalActions {
        #if DEBUG
        if FieldUITestHarness.isRequested {
            return FieldExternalActions(actions: uiTestExternalActions())
        }
        #endif
        return FieldExternalActions(actions: RadrootsAppleExternalActions())
    }

    func canOpenPublicNostrProfile(npub: String) async -> Bool {
        guard let destination = try? publicNostrProfileDestination(npub: npub) else {
            return false
        }
        return await actions.canOpen(destination).canOpen
    }

    func openAppSettings() async throws -> FieldExternalActionRequestRecord {
        let destination = RadrootsExternalActionDestination.appSettings
        try await actions.open(RadrootsExternalActionRequest(destination: destination))
        return FieldExternalActionRequestRecord(destination: destination)
    }

    func openPublicNostrProfile(npub: String) async throws -> FieldExternalActionRequestRecord {
        let destination = try publicNostrProfileDestination(npub: npub)
        try await actions.open(RadrootsExternalActionRequest(destination: destination))
        return FieldExternalActionRequestRecord(destination: destination)
    }

    private func publicNostrProfileDestination(npub: String) throws -> RadrootsExternalActionDestination {
        try RadrootsExternalActionDestination.nostr("nostr:\(npub)")
    }

    #if DEBUG
    private static func uiTestExternalActions() -> FieldUITestExternalActions {
        FieldUITestExternalActions(
            defaultCanOpen: uiTestCanOpen,
            openOutcome: uiTestOpenOutcome
        )
    }

    private static var uiTestCanOpen: Bool {
        if FieldUITestHarness.string("RADROOTS_FIELD_IOS_UI_TEST_EXTERNAL_ACTIONS_NOSTR_CAN_OPEN") != nil {
            return FieldUITestHarness.bool("RADROOTS_FIELD_IOS_UI_TEST_EXTERNAL_ACTIONS_NOSTR_CAN_OPEN", default: true)
        }
        if FieldUITestHarness.string("RADROOTS_FIELD_IOS_UI_TEST_EXTERNAL_ACTIONS_CAN_OPEN") != nil {
            return FieldUITestHarness.bool("RADROOTS_FIELD_IOS_UI_TEST_EXTERNAL_ACTIONS_CAN_OPEN", default: true)
        }
        return true
    }

    private static var uiTestOpenOutcome: Result<Void, RadrootsExternalActionError> {
        let raw = FieldUITestHarness.string("RADROOTS_FIELD_IOS_UI_TEST_EXTERNAL_ACTIONS_OPEN_OUTCOME")?.lowercased()
        switch raw {
        case nil, "", "success":
            return .success(())
        case "unavailable":
            return .failure(.unavailable("external actions are unavailable in this UI test"))
        case "transient_failure":
            return .failure(.transientFailure("external action failed in this UI test"))
        default:
            return .failure(.blockedByPolicy("unsupported UI-test external action outcome"))
        }
    }
    #endif
}
