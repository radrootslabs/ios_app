import Foundation
import RadrootsKit
import RadrootsKitTesting

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
        guard uiTestWasRequested else {
            return FieldExternalActions(actions: RadrootsAppleExternalActions())
        }
        return FieldExternalActions(actions: uiTestExternalActions())
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

    private static var uiTestWasRequested: Bool {
        let arguments = ProcessInfo.processInfo.arguments
        let environment = ProcessInfo.processInfo.environment
        return environment["RADROOTS_FIELD_IOS_UI_TEST"] == "true" ||
            arguments.contains("--radroots-field-ios-ui-test")
    }

    private static func uiTestExternalActions() -> RadrootsFakeExternalActions {
        RadrootsFakeExternalActions(
            defaultCanOpen: uiTestCanOpen,
            openOutcome: uiTestOpenOutcome
        )
    }

    private static var uiTestCanOpen: Bool {
        let environment = ProcessInfo.processInfo.environment
        if let raw = environment["RADROOTS_FIELD_IOS_UI_TEST_EXTERNAL_ACTIONS_NOSTR_CAN_OPEN"] {
            return parseBool(raw) ?? true
        }
        if let raw = environment["RADROOTS_FIELD_IOS_UI_TEST_EXTERNAL_ACTIONS_CAN_OPEN"] {
            return parseBool(raw) ?? true
        }
        return true
    }

    private static var uiTestOpenOutcome: Result<Void, RadrootsExternalActionError> {
        let raw = ProcessInfo.processInfo.environment["RADROOTS_FIELD_IOS_UI_TEST_EXTERNAL_ACTIONS_OPEN_OUTCOME"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
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

    private static func parseBool(_ raw: String) -> Bool? {
        switch raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "1", "true", "yes":
            true
        case "0", "false", "no":
            false
        default:
            nil
        }
    }
}
