import Foundation
import RadrootsKit

enum FieldIdentityCustodyError: LocalizedError {
    case missingKeychainServicePrefix
    case missingBundleIdentifier
    case invalidStoredSecret
    case missingSelectedSecret

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

    func saveSelectedSecretHex(_ secretHex: String) throws {
        let trimmed = secretHex.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw FieldIdentityCustodyError.missingSelectedSecret
        }
        try store.put(Data(trimmed.utf8), for: Self.selectedSecretKey, policy: .secureLocalSecret)
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

    private static var selectedSecretKey: RadrootsSecureStoreKey {
        RadrootsSecureStoreKey(namespace: namespace, name: selectedSecretName)
    }
}
