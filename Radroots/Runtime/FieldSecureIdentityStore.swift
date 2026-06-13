import Foundation
import RadrootsKit
import Security

enum FieldSecureIdentityStoreError: LocalizedError {
    case missingSecureStoreServicePrefix
    case missingBundleIdentifier
    case invalidStoredSecret
    case missingSelectedSecret
    case missingSecureStoreAccessPolicy
    case invalidSecureStoreAccessPolicy(String)
    case randomSecretGenerationFailed(Int32)

    var errorDescription: String? {
        switch self {
        case .missingSecureStoreServicePrefix:
            "Missing RADROOTS_FIELD_IOS_KEYCHAIN_SERVICE_PREFIX."
        case .missingBundleIdentifier:
            "Missing field iOS bundle identifier."
        case .invalidStoredSecret:
            "Stored Nostr identity secret is invalid."
        case .missingSelectedSecret:
            "No selected Nostr identity secret is available in secure store."
        case .missingSecureStoreAccessPolicy:
            "Missing RADROOTS_FIELD_IOS_KEYCHAIN_ACCESS_POLICY."
        case .invalidSecureStoreAccessPolicy(let value):
            "Invalid RADROOTS_FIELD_IOS_KEYCHAIN_ACCESS_POLICY: \(value)."
        case .randomSecretGenerationFailed(let status):
            "Secure Nostr identity generation failed with status \(status)."
        }
    }
}

enum FieldSecureIdentityAccessPolicy: String {
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

struct FieldSecureIdentityStore {
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

    static func configured() throws -> FieldSecureIdentityStore {
        guard let servicePrefix = BuildConfig.string(.keychainServicePrefix) else {
            throw FieldSecureIdentityStoreError.missingSecureStoreServicePrefix
        }
        return FieldSecureIdentityStore(servicePrefix: servicePrefix)
    }

    func loadSelectedSecretHex() throws -> String? {
        guard let data = try store.get(Self.selectedSecretKey) else {
            return nil
        }
        guard let value = String(data: data, encoding: .utf8) else {
            throw FieldSecureIdentityStoreError.invalidStoredSecret
        }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    func restoreStoredIdentity(
        label: String?,
        using service: FieldRuntimeService
    ) async throws -> NostrIdentityRecord {
        guard let secret = try loadSelectedSecretHex() else {
            throw FieldSecureIdentityStoreError.missingSelectedSecret
        }
        return try await service.nostrIdentityRestoreHostCustodySecret(
            secretKey: secret,
            label: label,
            makeSelected: true
        )
    }

    func importSecret(
        _ secret: String,
        label: String?,
        using service: FieldRuntimeService
    ) async throws -> NostrIdentityRecord {
        let trimmed = try normalizedSecret(secret)
        _ = try await service.nostrIdentityValidateHostCustodySecret(secretKey: trimmed)
        try saveSelectedSecret(trimmed)
        do {
            return try await service.nostrIdentityRestoreHostCustodySecret(
                secretKey: trimmed,
                label: label,
                makeSelected: true
            )
        } catch {
            try? deleteSelectedSecret()
            throw error
        }
    }

    func createIdentity(
        label: String?,
        using service: FieldRuntimeService
    ) async throws -> NostrIdentityRecord {
        var lastError: Error?
        for _ in 0..<8 {
            let secret = try Self.generateSecretHex()
            do {
                return try await importSecret(secret, label: label, using: service)
            } catch {
                lastError = error
            }
        }
        throw lastError ?? FieldSecureIdentityStoreError.missingSelectedSecret
    }

    func deleteSelectedSecret() throws {
        try store.delete(Self.selectedSecretKey)
    }

    func resetLocalState(bundleIdentifier: String) throws {
        let trimmedBundleIdentifier = bundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedBundleIdentifier.isEmpty else {
            throw FieldSecureIdentityStoreError.missingBundleIdentifier
        }
        try RadrootsAppLocalStateReset.reset(
            RadrootsAppLocalStateResetRequest(
                appIdentifier: trimmedBundleIdentifier,
                keychainServiceNames: [try Self.secureStoreServiceName(servicePrefix: servicePrefix)]
            )
        )
    }

    static func secureStoreServiceName(servicePrefix: String) throws -> String {
        try selectedSecretKey.serviceName(servicePrefix: servicePrefix)
    }

    static func configuredAccessPolicy() throws -> FieldSecureIdentityAccessPolicy {
        guard let rawValue = BuildConfig.string(.keychainAccessPolicy) else {
            throw FieldSecureIdentityStoreError.missingSecureStoreAccessPolicy
        }
        guard let policy = FieldSecureIdentityAccessPolicy(rawValue: rawValue) else {
            throw FieldSecureIdentityStoreError.invalidSecureStoreAccessPolicy(rawValue)
        }
        return policy
    }

    static func generateSecretHex() throws -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard status == errSecSuccess else {
            throw FieldSecureIdentityStoreError.randomSecretGenerationFailed(status)
        }
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    private func saveSelectedSecret(_ secret: String) throws {
        let trimmed = try normalizedSecret(secret)
        try store.put(
            Data(trimmed.utf8),
            for: Self.selectedSecretKey,
            policy: try Self.configuredAccessPolicy().storePolicy
        )
    }

    private func normalizedSecret(_ secret: String) throws -> String {
        let trimmed = secret.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw FieldSecureIdentityStoreError.missingSelectedSecret
        }
        return trimmed
    }

    private static var selectedSecretKey: RadrootsSecureStoreKey {
        RadrootsSecureStoreKey(namespace: namespace, name: selectedSecretName)
    }
}
