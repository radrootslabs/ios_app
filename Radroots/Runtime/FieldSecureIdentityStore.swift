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
    case forcedImportRestoreFailure

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
        case .forcedImportRestoreFailure:
            "Forced identity import restore failure."
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
        let previousSecret = try loadSelectedSecretHex()
        _ = try await service.nostrIdentityValidateHostCustodySecret(secretKey: trimmed)
        let stagedRecord = try await restoreHostCustodySecret(
            trimmed,
            label: label,
            makeSelected: false,
            using: service
        )
        do {
            try saveSelectedSecret(trimmed)
        } catch {
            await restorePreviousRuntimeIdentity(previousSecret, using: service)
            await removeStagedIdentityIfNeeded(stagedRecord, previousSecret: previousSecret, using: service)
            throw error
        }
        do {
            return try await restoreHostCustodySecret(
                trimmed,
                label: label,
                makeSelected: true,
                using: service
            )
        } catch {
            try? restorePreviousSelectedSecret(previousSecret)
            await restorePreviousRuntimeIdentity(previousSecret, using: service)
            await removeStagedIdentityIfNeeded(stagedRecord, previousSecret: previousSecret, using: service)
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

    private func restorePreviousSelectedSecret(_ previousSecret: String?) throws {
        if let previousSecret {
            try saveSelectedSecret(previousSecret)
        } else {
            try deleteSelectedSecret()
        }
    }

    private func restoreHostCustodySecret(
        _ secret: String,
        label: String?,
        makeSelected: Bool,
        using service: FieldRuntimeService
    ) async throws -> NostrIdentityRecord {
        #if DEBUG
        try FieldSecureIdentityImportRestoreFailureUITestHook.throwIfRequested(makeSelected: makeSelected)
        #endif
        return try await service.nostrIdentityRestoreHostCustodySecret(
            secretKey: secret,
            label: label,
            makeSelected: makeSelected
        )
    }

    private func restorePreviousRuntimeIdentity(
        _ previousSecret: String?,
        using service: FieldRuntimeService
    ) async {
        guard let previousSecret else {
            return
        }
        _ = try? await service.nostrIdentityRestoreHostCustodySecret(
            secretKey: previousSecret,
            label: nil,
            makeSelected: true
        )
    }

    private func removeStagedIdentityIfNeeded(
        _ stagedRecord: NostrIdentityRecord,
        previousSecret: String?,
        using service: FieldRuntimeService
    ) async {
        if let previousSecret,
           let previous = try? await service.nostrIdentityValidateHostCustodySecret(secretKey: previousSecret),
           previous.id == stagedRecord.id {
            return
        }
        try? await service.nostrIdentityRemove(identityId: stagedRecord.id)
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

#if DEBUG
private enum FieldSecureIdentityImportRestoreFailureUITestHook {
    private static let phaseKey = "RADROOTS_FIELD_IOS_UI_TEST_IDENTITY_IMPORT_RESTORE_FAILURE_PHASE"

    static func throwIfRequested(makeSelected: Bool) throws {
        guard FieldUITestHarness.isRequested,
              let rawPhase = FieldUITestHarness.string(phaseKey)?.lowercased() else {
            return
        }
        switch rawPhase {
        case "any":
            throw FieldSecureIdentityStoreError.forcedImportRestoreFailure
        case "stage" where !makeSelected:
            throw FieldSecureIdentityStoreError.forcedImportRestoreFailure
        case "select" where makeSelected:
            throw FieldSecureIdentityStoreError.forcedImportRestoreFailure
        default:
            return
        }
    }
}
#endif
