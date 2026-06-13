import Foundation

public final class FieldRuntimeService: @unchecked Sendable {
    private let runtime: RadrootsRuntime
    private let queue = DispatchQueue(label: "org.radroots.field_ios.runtime", qos: .userInitiated)

    public init(runtime: RadrootsRuntime) {
        self.runtime = runtime
    }

    func run<T>(_ work: @escaping @Sendable (RadrootsRuntime) throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do {
                    continuation.resume(returning: try work(self.runtime))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func runValue<T>(_ work: @escaping @Sendable (RadrootsRuntime) -> T) async -> T {
        await withCheckedContinuation { continuation in
            queue.async {
                continuation.resume(returning: work(self.runtime))
            }
        }
    }

    public func infoJson() async -> String {
        await runValue { $0.infoJson() }
    }

    public func nostrSetDefaultRelays(_ relays: [String]) async throws {
        try await run { try $0.nostrSetDefaultRelays(relays: relays) }
    }

    public func nostrConnectIfKeyPresent() async throws {
        try await run { try $0.nostrConnectIfKeyPresent() }
    }

    public func nostrConnectionStatus() async -> NostrConnectionStatus {
        await runValue { $0.nostrConnectionStatus() }
    }

    public func nostrIdentitySnapshot() async throws -> NostrIdentitySnapshot {
        try await run { try $0.nostrIdentitySnapshot() }
    }

    public func nostrIdentityList() async throws -> [NostrIdentityRecord] {
        try await run { try $0.nostrIdentityList() }
    }

    public func nostrIdentityValidateHostCustodySecret(secretKey: String) async throws -> NostrHostCustodyIdentity {
        try await run { try $0.nostrIdentityValidateHostCustodySecret(secretKey: secretKey) }
    }

    public func nostrIdentityRestoreHostCustodySecret(
        secretKey: String,
        label: String?,
        makeSelected: Bool
    ) async throws -> NostrIdentityRecord {
        try await run {
            try $0.nostrIdentityRestoreHostCustodySecret(
                secretKey: secretKey,
                label: label,
                makeSelected: makeSelected
            )
        }
    }

    public func nostrIdentityRemove(identityId: String) async throws {
        try await run { try $0.nostrIdentityRemove(identityId: identityId) }
    }

    public func nostrIdentityLockHostCustodyRuntime() async throws {
        try await run { try $0.nostrIdentityLockHostCustodyRuntime() }
    }

    public func nostrIdentityResetHostCustodyRuntime() async throws {
        try await run { try $0.nostrIdentityResetHostCustodyRuntime() }
    }

    public func nostrProfileForSelf() async -> NostrProfileEventMetadata? {
        await runValue { $0.nostrProfileForSelf() }
    }

    public func nostrFetchTextNotes(
        limit: UInt16,
        sinceUnix: UInt64?
    ) async throws -> [NostrPostEventMetadata] {
        try await run { try $0.nostrFetchTextNotes(limit: limit, sinceUnix: sinceUnix) }
    }

    public func nostrNextPostStreamEvent() async -> NostrPostEventMetadata? {
        await runValue { $0.nostrNextPostEvent() }
    }
}
