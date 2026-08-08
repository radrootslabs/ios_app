import Foundation
@testable import RadrootsApp
import RadrootsKit
import XCTest

final class RadrootsStateMigrationTests: XCTestCase {
    func testRelayValidationMatchesRustProfiles() throws {
        XCTAssertEqual(
            try RadrootsNetworkValidator.relays(
                ["wss://radroots.org", "WSS://WRITE.EXAMPLE:443/"],
                profile: .publicNetwork
            ),
            ["wss://write.example"]
        )
        XCTAssertEqual(
            try RadrootsNetworkValidator.relays(
                ["ws://127.0.0.1:7447"],
                profile: .simulator
            ),
            ["ws://127.0.0.1:7447"]
        )
        XCTAssertNoThrow(
            try RadrootsNetworkValidator.relays(
                ["wss://10.0.0.5:7447"],
                profile: .device
            )
        )
        for denied in [
            "ws://public.example",
            "wss://localhost",
            "wss://10.0.0.1",
            "wss://user@example.com",
            "wss://relay.example?token=value",
        ] {
            XCTAssertThrowsError(
                try RadrootsNetworkValidator.relays([denied], profile: .publicNetwork),
                "Expected public policy to deny \(denied)"
            )
        }
        XCTAssertThrowsError(
            try RadrootsNetworkValidator.relays(
                ["wss://127.0.0.1:7447"],
                profile: .device
            )
        )
    }

    func testLegacyRelayMigrationIsIdempotentAndCorruptionIsNotAbsence() async throws {
        let fixture = try StateFixture()
        defer { fixture.remove() }
        let fileAccess = RadrootsAppleFileAccess(roots: fixture.roots)
        try fileAccess.write(
            .inline(
                Data(
                    """
                    {"format":"radroots_field_ios_relay_settings_v1","relays":["ws://127.0.0.1:7447"]}
                    """.utf8
                )
            ),
            to: RadrootsFileReference(
                scope: .data,
                relativePath: "settings/relay_settings.json"
            )
        )
        let store = RadrootsConfigurationStore(
            bootstrap: fixture.bootstrap,
            roots: fixture.roots
        )
        let first = try await store.load()
        let second = try await store.load()
        XCTAssertEqual(first, second)
        XCTAssertEqual(first.writableRelays, ["ws://127.0.0.1:7447"])

        try fileAccess.write(
            .inline(Data("not-json".utf8)),
            to: RadrootsFileReference(
                scope: .data,
                relativePath: "settings/radroots_configuration_v2.json"
            )
        )
        do {
            _ = try await store.load()
            XCTFail("Corrupt stored configuration must fail closed")
        } catch {
            XCTAssertEqual(error as? RadrootsConfigurationError, .corruptStoredConfiguration)
        }
    }

    func testSourceGenerationAndVisualIdentitySurviveStoreRecreation() async throws {
        let fixture = try StateFixture()
        defer { fixture.remove() }
        let firstStore = RadrootsConfigurationStore(
            bootstrap: fixture.bootstrap,
            roots: fixture.roots
        )
        let first = try await firstStore.sourceGeneration()
        let secondStore = RadrootsConfigurationStore(
            bootstrap: fixture.bootstrap,
            roots: fixture.roots
        )
        let second = try await secondStore.sourceGeneration()
        XCTAssertEqual(first, second)

        let key = String(repeating: "ab", count: 32)
        XCTAssertEqual(
            RadrootsStableVisualIdentity(publicKeyHex: key),
            RadrootsStableVisualIdentity(publicKeyHex: key)
        )
        XCTAssertNotEqual(
            RadrootsStableVisualIdentity(publicKeyHex: key).digestHex,
            RadrootsStableVisualIdentity(publicKeyHex: String(repeating: "cd", count: 32)).digestHex
        )
    }

    func testLegacyIdentityMigrationIsTransactionalAndIdempotent() async throws {
        let secureStore = InMemorySecureStore()
        let metadataStore = InMemoryIdentityMetadataStore()
        let servicePrefix = "org.radroots.tests.identity.\(UUID().uuidString.lowercased())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: servicePrefix))
        defer {
            UserDefaults(suiteName: servicePrefix)?.removePersistentDomain(forName: servicePrefix)
        }
        let legacyKey = RadrootsSecureStoreKey(
            namespace: "nostr_identity",
            name: "selected_secret_hex"
        )
        try secureStore.put(
            Data(String(repeating: "01", count: 32).utf8),
            for: legacyKey,
            policy: .secureLocalSecret
        )
        let custody = try RadrootsIdentityCustody(
            configuration: RadrootsIdentityCustodyConfiguration(
                namespace: "radroots_identity_v1",
                secretPolicy: .secureLocalSecret
            ),
            secureStore: secureStore,
            metadataStore: metadataStore,
            userPresence: AllowingUserPresence()
        )
        let store = RadrootsIdentityStore(
            custody: custody,
            secureStore: secureStore,
            servicePrefix: servicePrefix,
            userDefaults: defaults
        )
        let first = try await store.loadAndMigrate()
        XCTAssertEqual(first.state, .recoveryRequired)
        XCTAssertTrue(try secureStore.contains(legacyKey))
        let migrated = try await store.recover()
        let second = try await store.loadAndMigrate()
        XCTAssertEqual(migrated.publicKeyHex, second.publicKeyHex)
        XCTAssertEqual(migrated.state, .unlocked)
        XCTAssertFalse(try secureStore.contains(legacyKey))
    }

    func testMalformedLegacyIdentityMetadataIsNotTreatedAsMissing() async throws {
        let secureStore = InMemorySecureStore()
        let servicePrefix = "org.radroots.tests.corrupt.\(UUID().uuidString.lowercased())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: servicePrefix))
        defer {
            UserDefaults(suiteName: servicePrefix)?.removePersistentDomain(forName: servicePrefix)
        }
        defaults.set(
            Data("not-json".utf8),
            forKey: "field_ios.identity.public_metadata.\(servicePrefix)"
        )
        let custody = try RadrootsIdentityCustody(
            configuration: RadrootsIdentityCustodyConfiguration(
                namespace: "radroots_identity_v1",
                secretPolicy: .secureLocalSecret
            ),
            secureStore: secureStore,
            metadataStore: InMemoryIdentityMetadataStore(),
            userPresence: AllowingUserPresence()
        )
        let store = RadrootsIdentityStore(
            custody: custody,
            secureStore: secureStore,
            servicePrefix: servicePrefix,
            userDefaults: defaults
        )
        do {
            _ = try await store.loadAndMigrate()
            XCTFail("Malformed legacy metadata must be classified as corrupt")
        } catch {
            XCTAssertEqual(error as? RadrootsIdentityStoreError, .corruptLegacyMetadata)
        }
    }
}

private struct StateFixture {
    let root: URL
    let roots: RadrootsAppleFileRoots
    let bootstrap: RadrootsConfigurationBootstrap

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("radroots-state-tests-\(UUID().uuidString.lowercased())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        roots = try RadrootsAppleFileRoots(
            appIdentifier: "org.radroots.tests",
            dataRoot: root.appendingPathComponent("data"),
            cacheRoot: root.appendingPathComponent("cache"),
            temporaryRoot: root.appendingPathComponent("tmp")
        )
        bootstrap = RadrootsConfigurationBootstrap(
            runtimeMode: "localhost-dev",
            relayURLs: ["ws://127.0.0.1:8080"],
            blossomOrigins: ["http://127.0.0.1:3000"],
            keychainServicePrefix: "org.radroots.tests",
            bundleIdentifier: "org.radroots.tests",
            appMetadata: RadrootsRuntimeAppMetadata(
                bundleIdentifier: "org.radroots.tests",
                version: "0.1.0-alpha",
                buildNumber: "1",
                buildSHA: nil
            )
        )
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }
}

private final class InMemorySecureStore: RadrootsSecureStore, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [RadrootsSecureStoreKey: Data] = [:]

    func put(
        _ value: Data,
        for key: RadrootsSecureStoreKey,
        policy _: RadrootsSecretAccessPolicy
    ) throws {
        lock.withLock { values[key] = value }
    }

    func contains(_ key: RadrootsSecureStoreKey) throws -> Bool {
        lock.withLock { values[key] != nil }
    }

    func get(_ key: RadrootsSecureStoreKey) throws -> Data? {
        lock.withLock { values[key] }
    }

    func delete(_ key: RadrootsSecureStoreKey) throws {
        lock.withLock { _ = values.removeValue(forKey: key) }
    }

    func deleteNamespace(_ namespace: String) throws {
        lock.withLock { values = values.filter { $0.key.namespace != namespace } }
    }
}

private final class InMemoryIdentityMetadataStore: RadrootsIdentityMetadataStore, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [RadrootsIdentityMetadataSlot: Data] = [:]

    func data(for slot: RadrootsIdentityMetadataSlot) throws -> Data? {
        lock.withLock { values[slot] }
    }

    func put(_ data: Data, for slot: RadrootsIdentityMetadataSlot) throws {
        lock.withLock { values[slot] = data }
    }

    func delete(_ slot: RadrootsIdentityMetadataSlot) throws {
        lock.withLock { _ = values.removeValue(forKey: slot) }
    }
}

private struct AllowingUserPresence: RadrootsUserPresence {
    func currentStatus() async throws -> RadrootsUserPresenceStatus {
        RadrootsUserPresenceStatus(
            support: .deviceCredential,
            biometryKind: .none,
            canEvaluateDeviceCredential: true,
            canEvaluateBiometrics: false
        )
    }

    func verify(_ request: RadrootsUserPresenceRequest) async throws -> RadrootsUserPresenceResult {
        RadrootsUserPresenceResult(policy: request.policy, verified: true)
    }
}
