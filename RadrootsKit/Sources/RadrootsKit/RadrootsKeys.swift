import Foundation
import Security

@MainActor
public final class RadrootsKeys: ObservableObject {
    @Published public private(set) var hasKey: Bool = false
    @Published public private(set) var npub: String?

    public init() {}

    public func loadFromKeychainIfPresent(runtime: RadrootsRuntime) {
        if let account = Keychain.activeAccount() ?? Keychain.accounts().first {
            if let data = Keychain.load(service: Keychain.service, account: account),
               let hex = String(data: data, encoding: .utf8) {
                try? runtime.keysLoadHex32(hex: hex)
            }
        }
        self.hasKey = runtime.keysIsLoaded()
        self.npub = runtime.keysNpub()
    }

    public func generateAndPersist(runtime: RadrootsRuntime) throws {
        _ = try runtime.keysGenerateInMemory()
        try persistCurrentKey(runtime: runtime, accountOverride: nil)
    }

    public func importSecretHex(hex: String, runtime: RadrootsRuntime) throws {
        try runtime.keysLoadHex32(hex: hex)
        try persistCurrentKey(runtime: runtime, accountOverride: nil)
    }

    private func persistCurrentKey(runtime: RadrootsRuntime, accountOverride: String?) throws {
        let hex = try runtime.keysExportSecretHex()
        let account = accountOverride ?? runtime.keysNpub() ?? "profile-\(Int(Date().timeIntervalSince1970))"
        Keychain.save(service: Keychain.service, account: account, data: Data(hex.utf8))
        Keychain.setActiveAccount(account)
        self.hasKey = runtime.keysIsLoaded()
        self.npub = runtime.keysNpub()
    }
}

private enum Keychain {
    static let service = "com.radroots.keys"
    static let activeService = "com.radroots.keys.active"
    static let activeAccountKey = "active"

    static func accounts() -> [String] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecMatchLimit as String: kSecMatchLimitAll,
            kSecReturnAttributes as String: true
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let items = result as? [[String: Any]] else { return [] }
        return items.compactMap { $0[kSecAttrAccount as String] as? String }
    }

    static func activeAccount() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: activeService,
            kSecAttrAccount as String: activeAccountKey,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnData as String: true
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func setActiveAccount(_ account: String) {
        let data = Data(account.utf8)
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: activeService,
            kSecAttrAccount as String: activeAccountKey
        ]
        SecItemDelete(base as CFDictionary)
        var query = base
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        query[kSecValueData as String] = data
        SecItemAdd(query as CFDictionary, nil)
    }

    static func load(service: String, account: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnData as String: true
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return data
    }

    static func save(service: String, account: String, data: Data) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecValueData as String: data
        ]
        SecItemAdd(query as CFDictionary, nil)
    }
}
