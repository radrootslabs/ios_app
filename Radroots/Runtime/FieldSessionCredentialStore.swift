import Foundation
import RadrootsKit

struct StoredFieldSessionTokens: Codable, Equatable {
    let accessToken: String
    let refreshToken: String
}

enum FieldSessionCredentialStoreError: LocalizedError {
    case missingKeychainServicePrefix

    var errorDescription: String? {
        switch self {
        case .missingKeychainServicePrefix:
            "No Keychain service prefix configured. Set 'RADROOTS_FIELD_IOS_KEYCHAIN_SERVICE_PREFIX'."
        }
    }
}

final class FieldSessionCredentialStore {
    private let secureStore: any RadrootsSecureStore
    private let key = RadrootsSecureStoreKey(namespace: "field_ios", name: "session_tokens")

    init(secureStore: (any RadrootsSecureStore)? = nil) throws {
        if let secureStore {
            self.secureStore = secureStore
        } else {
            guard let servicePrefix = BuildConfig.string(.keychainServicePrefix) else {
                throw FieldSessionCredentialStoreError.missingKeychainServicePrefix
            }
            self.secureStore = RadrootsAppleKeychainSecureStore(servicePrefix: servicePrefix)
        }
    }

    func load() throws -> StoredFieldSessionTokens? {
        guard let data = try secureStore.get(key) else { return nil }
        return try JSONDecoder().decode(StoredFieldSessionTokens.self, from: data)
    }

    func save(_ tokens: FieldSessionTokenBundle) throws {
        let stored = StoredFieldSessionTokens(
            accessToken: tokens.accessToken,
            refreshToken: tokens.refreshToken
        )
        let data = try JSONEncoder().encode(stored)
        try secureStore.put(data, for: key, policy: .secureLocalSecret)
    }

    func delete() throws {
        try secureStore.delete(key)
    }
}
