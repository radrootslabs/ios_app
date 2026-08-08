@testable import RadrootsApp
import XCTest

final class RadrootsSupportingStoreTests: XCTestCase {
    @MainActor
    func testSearchUsesCurrentContextDeduplicatesAndClearsEmptyQueries() async throws {
        let backend = SupportingBackend()
        let client = try await Self.startedClient(backend)
        let store = RadrootsSearchStore(runtimeClient: client, now: { 1_800_000_000 })
        store.configure(context: Self.context(id: "farm"))
        store.updateQuery(" carrots ")

        await store.search()

        XCTAssertEqual(store.state, .loaded)
        XCTAssertEqual(store.results.map(\.id), ["card", "profile"])
        let request = await backend.lastSearchRequest()
        XCTAssertEqual(request?.contextID, "farm")
        XCTAssertEqual(request?.query, "carrots")
        store.updateQuery("   ")
        XCTAssertEqual(store.state, .idle)
        XCTAssertTrue(store.results.isEmpty)
        _ = try await client.stop()
    }

    @MainActor
    func testSearchContextChangeFencesLateResults() async throws {
        let backend = SupportingBackend(searchDelayNanoseconds: 40_000_000)
        let client = try await Self.startedClient(backend)
        let store = RadrootsSearchStore(runtimeClient: client, now: { 1_800_000_000 })
        store.configure(context: Self.context(id: "first"))
        store.updateQuery("carrots")

        let search = Task { await store.search() }
        try await Task.sleep(nanoseconds: 2_000_000)
        store.configure(context: Self.context(id: "second"))
        await search.value

        XCTAssertTrue(store.results.isEmpty)
        XCTAssertEqual(store.state, .idle)
        _ = try await client.stop()
    }

    @MainActor
    func testMePreservesAdoptedProfileFieldsAndCurrentCards() async throws {
        let backend = SupportingBackend()
        let client = try await Self.startedClient(backend)
        let store = RadrootsMeStore(runtimeClient: client, now: { 1_800_000_000 })
        store.configure(context: Self.context(id: "farm"))

        await store.start()

        let snapshot = try XCTUnwrap(store.snapshot)
        XCTAssertEqual(snapshot.profile?.displayName, "Moss Farm")
        XCTAssertEqual(snapshot.profile?.about, "Local roots")
        XCTAssertEqual(snapshot.profile?.nip05, "moss@example.com")
        XCTAssertEqual(snapshot.profile?.website, "https://moss.example")
        XCTAssertEqual(snapshot.profile?.lightningAddress, "moss@example.com")
        XCTAssertEqual(snapshot.cards.map(\.id), ["card"])
        store.stop()
        _ = try await client.stop()
    }

    func testVisualIdentityIsStableAndKeyBound() {
        let first = RadrootsStableVisualIdentity(publicKeyHex: String(repeating: "a", count: 64))
        let repeated = RadrootsStableVisualIdentity(publicKeyHex: String(repeating: "a", count: 64))
        let second = RadrootsStableVisualIdentity(publicKeyHex: String(repeating: "b", count: 64))

        XCTAssertEqual(first, repeated)
        XCTAssertNotEqual(first.digestHex, second.digestHex)
        XCTAssertTrue((0 ..< 12).contains(first.paletteIndex))
    }

    private static func startedClient(_ backend: SupportingBackend) async throws -> RadrootsRuntimeClient {
        let client = RadrootsRuntimeClient { _ in
            await RadrootsRuntimeBackendStart(backend: backend, snapshot: backend.snapshotValue())
        }
        _ = try await client.start(configuration: configuration())
        return client
    }

    private static func configuration() -> RadrootsRuntimeLaunchConfiguration {
        RadrootsRuntimeLaunchConfiguration(
            applicationSupportDirectory: "/tmp/radroots-supporting-tests",
            publicKeyHex: String(repeating: "a", count: 64),
            sourceGenerationHex: String(repeating: "c", count: 64),
            sourceGenerationCreatedAtUnixMilliseconds: 1,
            protectedData: .available,
            networkProfile: .simulator,
            writableRelays: ["ws://127.0.0.1:7447"],
            blossomOrigins: ["http://127.0.0.1:3000"],
            app: RadrootsRuntimeAppMetadata(
                bundleIdentifier: "org.radroots.supporting-tests",
                version: "0.1.0-alpha",
                buildNumber: "1",
                buildSHA: nil
            ),
            signerGeneration: "supporting-tests",
            signer: SupportingSigner()
        )
    }

    private static func context(id: String) -> RadrootsLocalNetwork {
        RadrootsLocalNetwork(
            schemaVersion: 1,
            id: id,
            label: "Farm",
            relayURLs: ["ws://127.0.0.1:7447"],
            locality: "Metchosin",
            followedAuthors: [],
            generation: 1
        )
    }
}

private struct SupportingSigner: RadrootsRuntimeSigner {
    func availability() -> RadrootsRuntimeSignerAvailability {
        .ready
    }

    func sign(_: RadrootsRuntimeSigningRequest) -> RadrootsRuntimeSigningOutcome {
        .failed
    }
}

private actor SupportingBackend: RadrootsRuntimeBackend {
    struct SearchRequest: Sendable {
        let contextID: String
        let query: String
    }

    private let searchDelayNanoseconds: UInt64
    private var request: SearchRequest?
    private var closed = false

    init(searchDelayNanoseconds: UInt64 = 0) {
        self.searchDelayNanoseconds = searchDelayNanoseconds
    }

    func snapshotValue() -> RadrootsRuntimeSnapshot {
        RadrootsRuntimeSnapshot(
            identity: RadrootsRuntimeIdentity(
                publicKeyHex: String(repeating: "a", count: 64),
                hostSignerConfigured: true
            ),
            relay: nil,
            crateName: "radroots_mobile_ffi",
            crateVersion: "0.1.0-alpha",
            isClosed: closed
        )
    }

    func snapshot() -> RadrootsRuntimeSnapshot {
        snapshotValue()
    }

    func todayPage(request _: RadrootsTodayPageRequest) throws -> RadrootsTodayPage {
        throw unsupported()
    }

    func refreshToday(
        context _: RadrootsLocalNetwork,
        nowUnixSeconds _: UInt64,
        update _: RadrootsTodayProjectionUpdate
    ) throws -> RadrootsTodayRefreshReceipt {
        throw unsupported()
    }

    func search(
        context: RadrootsLocalNetwork,
        query: String,
        limit _: UInt16,
        asOfUnixSeconds _: UInt64
    ) async throws -> [RadrootsSearchResult] {
        request = SearchRequest(contextID: context.id, query: query)
        if searchDelayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: searchDelayNanoseconds)
        }
        let card = Self.card()
        let profile = Self.profile()
        return [
            RadrootsSearchResult(type: .card, id: "card", card: card, profile: nil),
            RadrootsSearchResult(type: .card, id: "card", card: card, profile: nil),
            RadrootsSearchResult(type: .profile, id: "profile", card: nil, profile: profile),
        ]
    }

    func me(
        context _: RadrootsLocalNetwork,
        asOfUnixSeconds _: UInt64
    ) -> RadrootsMeSnapshot {
        RadrootsMeSnapshot(
            publicKey: String(repeating: "a", count: 64),
            profile: Self.profile(),
            cards: [Self.card()]
        )
    }

    func subscribe(
        bufferCapacity _: Int,
        receive _: @escaping @Sendable (RadrootsRuntimeChange) async -> Void
    ) -> any RadrootsRuntimeSubscriptionToken {
        SupportingSubscriptionToken()
    }

    func shutdown() -> RadrootsRuntimeShutdownReceipt {
        let wasClosed = closed
        closed = true
        return RadrootsRuntimeShutdownReceipt(state: "closed", alreadyClosed: wasClosed)
    }

    func lastSearchRequest() -> SearchRequest? {
        request
    }

    private func unsupported() -> RadrootsRuntimeFailure {
        .local(
            operation: "test.supporting",
            code: "test.unsupported",
            safeMessage: "Unsupported test operation."
        )
    }

    private static func profile() -> RadrootsProfileSummary {
        RadrootsProfileSummary(
            authorPublicKey: String(repeating: "a", count: 64),
            name: "moss",
            displayName: "Moss Farm",
            about: "Local roots",
            picture: nil,
            banner: nil,
            nip05: "moss@example.com",
            website: "https://moss.example",
            lightningAddress: "moss@example.com"
        )
    }

    private static func card() -> RadrootsTodayCard {
        RadrootsTodayCard(
            id: "card",
            type: .foodAvailability,
            sourceEventID: String(repeating: "e", count: 64),
            sourceAddress: nil,
            authorPublicKey: String(repeating: "a", count: 64),
            contractID: "radroots.food_availability.v1",
            title: "Carrots",
            content: "Freshly picked",
            authoredAtUnixSeconds: 1_800_000_000,
            effectiveAtUnixSeconds: 1_800_000_000,
            eventStartUnixSeconds: nil,
            eventEndUnixSeconds: nil,
            location: "Metchosin",
            priceAmount: "3",
            priceCurrency: "CAD",
            priceUnit: "lb",
            quantity: "12",
            contextRank: 1,
            inclusionReason: "local",
            media: [],
            lifecycle: .active,
            rankDigest: nil,
            authorProfile: profile(),
            thread: [],
            localOperationID: nil,
            localOperationState: nil
        )
    }
}

private actor SupportingSubscriptionToken: RadrootsRuntimeSubscriptionToken {
    func cancel() {}
}
