import XCTest
@testable import Radroots

final class SharedEngineLifecycleTests: XCTestCase {
    private let secret = String(repeating: "01", count: 32)

    func testIdentityRemainsHostCustodiedAndLockClearsRuntimeState() async throws {
        let service = try FieldRuntimeService(runtime: RadrootsRuntime())
        let validated = try await service.nostrIdentityValidateHostCustodySecret(secretKey: secret)
        let initialSnapshot = try await service.nostrIdentitySnapshot()
        XCTAssertFalse(initialSnapshot.hasSelectedSigningIdentity)

        let selected = try await service.nostrIdentityRestoreHostCustodySecret(
            secretKey: secret,
            label: "Simulator",
            makeSelected: true
        )
        XCTAssertEqual(selected.id, validated.id)
        let selectedSnapshot = try await service.nostrIdentitySnapshot()
        XCTAssertTrue(selectedSnapshot.hasSelectedSigningIdentity)

        try await service.nostrIdentityLockHostCustodyRuntime()
        let lockedSnapshot = try await service.nostrIdentitySnapshot()
        XCTAssertFalse(lockedSnapshot.hasSelectedSigningIdentity)
        _ = try await service.shutdown()
    }

    func testRelayStatusReportsCapabilitiesWithoutConnectionCounts() async throws {
        let service = try FieldRuntimeService(runtime: RadrootsRuntime())
        try await service.nostrSetDefaultRelays(["wss://relay.damus.io"])

        let status = try await service.nostrConnectionStatus()
        XCTAssertTrue(status.configured)
        XCTAssertTrue(status.sourceAvailable)
        XCTAssertTrue(status.sinkAvailable)
        XCTAssertNil(status.lastError)
        _ = try await service.shutdown()
    }

    func testShutdownIsExplicitAndIdempotent() async throws {
        let service = try FieldRuntimeService(runtime: RadrootsRuntime())
        let first = try await service.shutdown()
        let second = try await service.shutdown()

        XCTAssertEqual(first.state, "closed")
        XCTAssertFalse(first.alreadyClosed)
        XCTAssertEqual(second.state, "closed")
        XCTAssertTrue(second.alreadyClosed)
    }
}
