import Foundation

struct FieldIdentityPublicMetadata: Codable, Equatable, Sendable {
    let selectedIdentityId: String
    let publicKeyHex: String
    let publicKeyNpub: String
    let label: String?
    let updatedAtUnix: UInt64

    init(record: NostrIdentityRecord, updatedAtUnix: UInt64 = UInt64(Date().timeIntervalSince1970)) {
        self.selectedIdentityId = record.id
        self.publicKeyHex = record.publicKeyHex
        self.publicKeyNpub = record.publicKeyNpub
        self.label = record.label
        self.updatedAtUnix = updatedAtUnix
    }
}

struct FieldIdentityPublicMetadataStore {
    private let userDefaults: UserDefaults
    private let key: String

    init(servicePrefix: String, userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        self.key = "field_ios.identity.public_metadata.\(servicePrefix)"
    }

    static func configured() throws -> FieldIdentityPublicMetadataStore {
        guard let servicePrefix = BuildConfig.string(.keychainServicePrefix) else {
            throw FieldIdentityCustodyError.missingKeychainServicePrefix
        }
        return FieldIdentityPublicMetadataStore(servicePrefix: servicePrefix)
    }

    func load() -> FieldIdentityPublicMetadata? {
        guard let data = userDefaults.data(forKey: key) else {
            return nil
        }
        return try? JSONDecoder().decode(FieldIdentityPublicMetadata.self, from: data)
    }

    func save(_ metadata: FieldIdentityPublicMetadata) throws {
        let data = try JSONEncoder().encode(metadata)
        userDefaults.set(data, forKey: key)
    }

    func delete() {
        userDefaults.removeObject(forKey: key)
    }
}
