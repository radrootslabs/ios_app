import Foundation
import RadrootsKit
import Security

enum FieldIdentityCustodyError: LocalizedError {
    case missingKeychainServicePrefix
    case missingBundleIdentifier
    case invalidStoredSecret
    case missingSelectedSecret
    case missingKeychainAccessPolicy
    case invalidKeychainAccessPolicy(String)
    case randomSecretGenerationFailed(Int32)

    var errorDescription: String? {
        switch self {
        case .missingKeychainServicePrefix:
            "Missing RADROOTS_FIELD_IOS_KEYCHAIN_SERVICE_PREFIX."
        case .missingBundleIdentifier:
            "Missing field iOS bundle identifier."
        case .invalidStoredSecret:
            "Stored Nostr identity secret is invalid."
        case .missingSelectedSecret:
            "No selected Nostr identity secret is available to secure."
        case .missingKeychainAccessPolicy:
            "Missing RADROOTS_FIELD_IOS_KEYCHAIN_ACCESS_POLICY."
        case .invalidKeychainAccessPolicy(let value):
            "Invalid RADROOTS_FIELD_IOS_KEYCHAIN_ACCESS_POLICY: \(value)."
        case .randomSecretGenerationFailed(let status):
            "Secure Nostr identity generation failed with status \(status)."
        }
    }
}

enum FieldIdentityKeychainAccessPolicy: String {
    case userPresenceLocal = "user_presence_local"
    case secureLocal = "secure_local"

    var storePolicy: RadrootsSecretAccessPolicy {
        switch self {
        case .userPresenceLocal:
            .userPresenceLocalSecret
        case .secureLocal:
            .secureLocalSecret
        }
    }
}

struct FieldIdentityCustodyStore {
    static let namespace = "nostr_identity"
    static let selectedSecretName = "selected_secret_hex"

    let servicePrefix: String
    private let store: any RadrootsSecureStore

    init(servicePrefix: String) {
        self.servicePrefix = servicePrefix
        self.store = RadrootsAppleKeychainSecureStore(servicePrefix: servicePrefix)
    }

    init(servicePrefix: String, store: any RadrootsSecureStore) {
        self.servicePrefix = servicePrefix
        self.store = store
    }

    static func configured() throws -> FieldIdentityCustodyStore {
        guard let servicePrefix = BuildConfig.string(.keychainServicePrefix) else {
            throw FieldIdentityCustodyError.missingKeychainServicePrefix
        }
        return FieldIdentityCustodyStore(servicePrefix: servicePrefix)
    }

    func loadSelectedSecretHex() throws -> String? {
        guard let data = try store.get(Self.selectedSecretKey) else {
            return nil
        }
        guard let value = String(data: data, encoding: .utf8) else {
            throw FieldIdentityCustodyError.invalidStoredSecret
        }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    func saveSelectedSecret(_ secret: String) throws {
        let trimmed = secret.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw FieldIdentityCustodyError.missingSelectedSecret
        }
        try store.put(
            Data(trimmed.utf8),
            for: Self.selectedSecretKey,
            policy: try Self.configuredAccessPolicy().storePolicy
        )
    }

    func deleteSelectedSecret() throws {
        try store.delete(Self.selectedSecretKey)
    }

    func resetLocalState(bundleIdentifier: String) throws {
        let trimmedBundleIdentifier = bundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedBundleIdentifier.isEmpty else {
            throw FieldIdentityCustodyError.missingBundleIdentifier
        }
        try RadrootsAppLocalStateReset.reset(
            RadrootsAppLocalStateResetRequest(
                appIdentifier: trimmedBundleIdentifier,
                keychainServiceNames: [try Self.keychainServiceName(servicePrefix: servicePrefix)]
            )
        )
    }

    static func keychainServiceName(servicePrefix: String) throws -> String {
        try selectedSecretKey.serviceName(servicePrefix: servicePrefix)
    }

    static func configuredAccessPolicy() throws -> FieldIdentityKeychainAccessPolicy {
        guard let rawValue = BuildConfig.string(.keychainAccessPolicy) else {
            throw FieldIdentityCustodyError.missingKeychainAccessPolicy
        }
        guard let policy = FieldIdentityKeychainAccessPolicy(rawValue: rawValue) else {
            throw FieldIdentityCustodyError.invalidKeychainAccessPolicy(rawValue)
        }
        return policy
    }

    static func generateSecretHex() throws -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard status == errSecSuccess else {
            throw FieldIdentityCustodyError.randomSecretGenerationFailed(status)
        }
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    private static var selectedSecretKey: RadrootsSecureStoreKey {
        RadrootsSecureStoreKey(namespace: namespace, name: selectedSecretName)
    }
}
