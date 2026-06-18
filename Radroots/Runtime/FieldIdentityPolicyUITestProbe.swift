#if DEBUG
import Foundation
import RadrootsKit

enum FieldIdentityPolicyUITestProbe {
    private static let enabledKey = "RADROOTS_FIELD_IOS_UI_TEST_IDENTITY_POLICY_PROBE"

    static var isRequested: Bool {
        FieldUITestHarness.string(enabledKey) == "true"
    }

    static func value() throws -> String? {
        guard isRequested else {
            return nil
        }
        let configuredPolicy = try FieldSecureIdentityStore.configuredAccessPolicy()
        let storePolicy = configuredPolicy.storePolicy
        return [
            "configured_policy=\(configuredPolicy.rawValue)",
            "store_policy_accessibility=\(accessibilityValue(storePolicy.accessibility))",
            "store_policy_device_local_only=\(storePolicy.deviceLocalOnly)",
            "store_policy_user_presence_required=\(storePolicy.userPresenceRequired)"
        ].joined(separator: ";")
    }

    private static func accessibilityValue(_ accessibility: RadrootsSecretAccessibility) -> String {
        switch accessibility {
        case .whenUnlocked:
            "when_unlocked"
        case .afterFirstUnlock:
            "after_first_unlock"
        }
    }
}
#endif
