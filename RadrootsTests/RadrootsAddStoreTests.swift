@testable import Radroots
import XCTest

final class RadrootsAddStoreTests: XCTestCase {
    @MainActor
    func testAllFiveFormsCompleteThroughRuntimeAndSubmittedSnapshotsFreeze() async throws {
        let backend = AddBackend()
        let client = try await Self.startedClient(backend)
        let store = RadrootsAddStore(
            runtimeClient: client,
            media: AddMediaHarness(),
            now: { 1_800_000_000 }
        )
        await store.configure(snapshot: backend.snapshot())
        await store.start()

        for type in RadrootsAddCommandType.allCases {
            store.newDraft(type: type)
            configure(store, type: type)
            if type == .createPhotoUpdate {
                await store.importPhotos()
                XCTAssertEqual(store.form.media.count, 1)
            }
            await store.submit()
            XCTAssertEqual(store.activeDraft?.commandType, type)
            XCTAssertEqual(store.activeDraft?.state, .complete)
            XCTAssertEqual(store.activeDraft?.form, store.form)
        }

        let frozen = store.form
        store.updateForm(\.content, "mutated after submit")
        store.selectType(.createUpdate)
        XCTAssertEqual(store.form, frozen)
        XCTAssertFalse(store.isFormEditable)
        XCTAssertEqual(store.drafts.filter { $0.kind == .add }.count, 5)
        _ = try await client.stop()
    }

    @MainActor
    func testOfflineSubmitPersistsQueuedSnapshotForRetryAndReopen() async throws {
        let backend = AddBackend(advanceOffline: true)
        let client = try await Self.startedClient(backend)
        let store = RadrootsAddStore(runtimeClient: client, now: { 1_800_000_000 })
        await store.configure(snapshot: backend.snapshot())
        await store.start()
        store.updateForm(\.content, "Saved while the farm is offline")

        await store.submit()

        let queued = try XCTUnwrap(store.activeDraft)
        XCTAssertEqual(queued.state, .queued)
        XCTAssertEqual(queued.form?.content, "Saved while the farm is offline")
        XCTAssertTrue(store.message?.contains("Saved for retry") == true)
        store.reopen(queued)
        XCTAssertEqual(store.form, queued.form)
        XCTAssertFalse(store.isFormEditable)
        _ = try await client.stop()
    }

    @MainActor
    func testRetractionAndRevisedCopyRemainIndependentHonestOperations() async throws {
        let backend = AddBackend(advanceOffline: true)
        let client = try await Self.startedClient(backend)
        let store = RadrootsAddStore(runtimeClient: client, now: { 1_800_000_000 })
        await store.configure(snapshot: backend.snapshot())
        await store.start()

        await store.retractAndRevise(Self.card())

        XCTAssertEqual(store.drafts.first(where: { $0.kind == .retraction })?.state, .queued)
        XCTAssertNil(store.activeDraft)
        XCTAssertEqual(store.form.commandType, .createFoodAvailability)
        XCTAssertEqual(store.form.identifier, "carrots")
        XCTAssertTrue(store.message?.contains("separate revised copy") == true)
        _ = try await client.stop()
    }

    @MainActor
    func testStopFencesLateDraftCompletion() async throws {
        let backend = AddBackend(saveDelayNanoseconds: 50_000_000)
        let client = try await Self.startedClient(backend)
        let store = RadrootsAddStore(runtimeClient: client, now: { 1_800_000_000 })
        await store.configure(snapshot: backend.snapshot())
        await store.start()
        store.updateForm(\.content, "Late draft")

        let save = Task { await store.save() }
        try await Task.sleep(nanoseconds: 2_000_000)
        store.stop()
        await save.value

        XCTAssertNil(store.activeDraft)
        XCTAssertFalse(store.isWorking)
        _ = try await client.stop()
    }

    @MainActor
    private func configure(_ store: RadrootsAddStore, type: RadrootsAddCommandType) {
        switch type {
        case .createUpdate:
            store.updateForm(\.content, "Harvest update")
        case .createPhotoUpdate:
            store.updateForm(\.content, "Carrots from today")
        case .createAsk:
            store.updateForm(\.content, "Who has seed potatoes?")
        case .createEvent:
            store.updateForm(\.identifier, Optional("market-day"))
            store.updateForm(\.title, Optional("Market day"))
            store.updateForm(\.eventTiming, Optional(RadrootsEventTiming.timed))
            store.updateForm(\.eventStartUnixSeconds, Optional(UInt64(1_800_003_600)))
            store.updateForm(\.location, Optional("Town square"))
        case .createFoodAvailability:
            store.updateForm(\.identifier, Optional("carrots"))
            store.updateForm(\.title, Optional("Carrots"))
            store.updateForm(\.location, Optional("Town square"))
            store.updateForm(\.priceAmount, Optional("3"))
            store.updateForm(\.currency, Optional("CAD"))
            store.updateForm(\.unit, Optional("lb"))
        }
    }

    private static func startedClient(_ backend: AddBackend) async throws -> RadrootsRuntimeClient {
        let client = RadrootsRuntimeClient { _ in
            await RadrootsRuntimeBackendStart(backend: backend, snapshot: backend.snapshot())
        }
        _ = try await client.start(configuration: configuration())
        return client
    }

    private static func configuration() -> RadrootsRuntimeLaunchConfiguration {
        RadrootsRuntimeLaunchConfiguration(
            applicationSupportDirectory: "/tmp/radroots-add-tests",
            publicKeyHex: String(repeating: "ab", count: 32),
            sourceGenerationHex: String(repeating: "cd", count: 32),
            sourceGenerationCreatedAtUnixMilliseconds: 1,
            protectedData: .available,
            networkProfile: .simulator,
            writableRelays: ["ws://127.0.0.1:7447"],
            blossomOrigins: ["http://127.0.0.1:3000"],
            app: RadrootsRuntimeAppMetadata(
                bundleIdentifier: "org.radroots.add-tests",
                version: "0.1.0-alpha",
                buildNumber: "1",
                buildSHA: nil
            ),
            signerGeneration: "add-tests",
            signer: AddSigner()
        )
    }

    private static func card() -> RadrootsTodayCard {
        RadrootsTodayCard(
            id: String(repeating: "c", count: 64),
            type: .foodAvailability,
            sourceEventID: String(repeating: "e", count: 64),
            sourceAddress: "30402:\(String(repeating: "a", count: 64)):carrots",
            authorPublicKey: String(repeating: "a", count: 64),
            contractID: "radroots.food_availability.v1",
            title: "Carrots",
            content: "Freshly picked",
            authoredAtUnixSeconds: 1_800_000_000,
            effectiveAtUnixSeconds: 1_800_000_000,
            eventStartUnixSeconds: nil,
            eventEndUnixSeconds: nil,
            location: "Town square",
            priceAmount: "3",
            priceCurrency: "CAD",
            priceUnit: "lb",
            quantity: "12",
            contextRank: 1,
            inclusionReason: "local",
            media: [],
            lifecycle: .active,
            rankDigest: nil,
            authorProfile: nil,
            thread: [],
            localOperationID: nil,
            localOperationState: nil
        )
    }
}

private struct AddSigner: RadrootsRuntimeSigner {
    func availability() async -> RadrootsRuntimeSignerAvailability {
        .ready
    }

    func sign(_: RadrootsRuntimeSigningRequest) async -> RadrootsRuntimeSigningOutcome {
        .failed
    }
}

private actor AddMediaHarness: RadrootsAddMediaHandling {
    private let item = RadrootsPreparedMedia(
        opaqueReference: "media:\(String(repeating: "0", count: 64))",
        url: "http://127.0.0.1:3000/\(String(repeating: "0", count: 64)).png",
        sha256: String(repeating: "0", count: 64),
        mediaType: "image/png",
        byteSize: 4,
        width: 2,
        height: 2,
        alt: "Carrots",
        preparedAtUnixSeconds: 1_800_000_000
    )

    func support() -> RadrootsAddMediaSupport {
        .init(library: true, camera: true)
    }

    func importImages(limit _: Int) -> [RadrootsPreparedMedia] {
        [item]
    }

    func captureImage() -> RadrootsPreparedMedia {
        item
    }

    func open(_ media: [RadrootsPreparedMedia]) -> RadrootsOpenedMedia {
        RadrootsOpenedMedia(
            handles: media.map { RadrootsPreparedMediaHandle(media: $0, fileDescriptor: 1) },
            files: []
        )
    }
}

private actor AddBackend: RadrootsRuntimeBackend {
    private let advanceOffline: Bool
    private let saveDelayNanoseconds: UInt64
    private var values: [String: RadrootsDraftStatus] = [:]
    private var closed = false

    init(advanceOffline: Bool = false, saveDelayNanoseconds: UInt64 = 0) {
        self.advanceOffline = advanceOffline
        self.saveDelayNanoseconds = saveDelayNanoseconds
    }

    func snapshot() -> RadrootsRuntimeSnapshot {
        RadrootsRuntimeSnapshot(
            identity: RadrootsRuntimeIdentity(
                publicKeyHex: String(repeating: "ab", count: 32),
                hostSignerConfigured: true
            ),
            relay: RadrootsRelayStatus(
                profile: "simulator",
                state: "configured",
                readAvailability: "unobserved",
                writeAvailability: "unobserved",
                relays: [
                    RadrootsRelayEndpointStatus(
                        url: "ws://127.0.0.1:7447",
                        access: "read_write",
                        readState: "unobserved",
                        writeState: "unobserved",
                        readLastAttemptUnixMilliseconds: nil,
                        writeLastAttemptUnixMilliseconds: nil,
                        readNextAttemptUnixMilliseconds: nil,
                        writeNextAttemptUnixMilliseconds: nil
                    ),
                ]
            ),
            crateName: "radroots_mobile_ffi",
            crateVersion: "0.1.0-alpha",
            isClosed: closed
        )
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

    func addSchemas() -> [RadrootsAddSchema] {
        RadrootsAddCommandType.allCases.map {
            RadrootsAddSchema(schemaVersion: 1, commandType: $0, label: $0.label, fields: [])
        }
    }

    func saveDraft(
        id: String,
        input: RadrootsAddRuntimeInput,
        authoredAtUnixSeconds _: UInt64,
        expectedRevision: UInt64?,
        persistedAtUnixMilliseconds: UInt64
    ) async throws -> RadrootsDraftStatus {
        if saveDelayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: saveDelayNanoseconds)
        }
        let status = makeStatus(
            id: id,
            revision: (expectedRevision ?? 0) + 1,
            kind: .add,
            commandType: input.form.commandType,
            form: input.form,
            state: input.form.media.isEmpty ? .draft : .mediaPreparing,
            updatedAt: persistedAtUnixMilliseconds,
            media: input.form.media.map {
                RadrootsDraftMediaStatus(
                    url: $0.url,
                    stage: .pending,
                    uploadAttempts: 0,
                    verifiedAtUnixMilliseconds: nil,
                    possibleOrphan: false,
                    orphanReasonCode: nil,
                    orphanRecordedAtUnixMilliseconds: nil
                )
            }
        )
        values[id] = status
        return status
    }

    func saveRetractionDraft(
        id: String,
        input: RadrootsRetractionDraftInput,
        authoredAtUnixSeconds _: UInt64,
        persistedAtUnixMilliseconds: UInt64
    ) -> RadrootsDraftStatus {
        let status = makeStatus(
            id: id,
            revision: 1,
            kind: .retraction,
            commandType: input.commandType,
            form: nil,
            state: .draft,
            updatedAt: persistedAtUnixMilliseconds,
            media: []
        )
        values[id] = status
        return status
    }

    func draftStatus(id: String) throws -> RadrootsDraftStatus {
        guard let value = values[id] else { throw unsupported() }
        return value
    }

    func draftHeads(limit: UInt16) -> [RadrootsDraftStatus] {
        Array(values.values.prefix(Int(limit)))
    }

    func queueDraft(
        id: String,
        expectedRevision: UInt64,
        policy _: RadrootsQueuePolicy,
        queuedAtUnixMilliseconds: UInt64
    ) throws -> RadrootsDraftStatus {
        let current = try draftStatus(id: id)
        guard current.revision == expectedRevision else { throw unsupported() }
        let value = replacing(current, revision: current.revision + 1, state: .queued, updatedAt: queuedAtUnixMilliseconds)
        values[id] = value
        return value
    }

    func recoverDraftQueue(id: String, recoveredAtUnixMilliseconds: UInt64) throws -> RadrootsDraftStatus {
        let current = try draftStatus(id: id)
        let value = replacing(current, revision: current.revision + 1, state: .queued, updatedAt: recoveredAtUnixMilliseconds)
        values[id] = value
        return value
    }

    func uploadDraftMedia(input: RadrootsBlossomUploadInput) throws -> RadrootsDraftStatus {
        let current = try draftStatus(id: input.draftID)
        let verified = current.media.map {
            RadrootsDraftMediaStatus(
                url: $0.url,
                stage: .verified,
                uploadAttempts: $0.uploadAttempts + 1,
                verifiedAtUnixMilliseconds: input.verifiedAtUnixMilliseconds,
                possibleOrphan: false,
                orphanReasonCode: nil,
                orphanRecordedAtUnixMilliseconds: nil
            )
        }
        let value = replacing(
            current,
            revision: current.revision + 1,
            state: .readyToSign,
            updatedAt: input.updatedAtUnixMilliseconds,
            media: verified
        )
        values[current.id] = value
        return value
    }

    func advanceDraft(id: String, expectedRevision: UInt64) throws -> RadrootsDraftStatus {
        if advanceOffline {
            throw RadrootsRuntimeFailure(
                schemaVersion: 1,
                code: "test.offline",
                category: "relay",
                retryable: true,
                recoveryActions: ["retry"],
                operationID: id,
                capabilityID: "nostr_sink",
                safeMessage: "The relay is offline."
            )
        }
        let current = try draftStatus(id: id)
        let value = replacing(current, revision: expectedRevision, state: .complete, updatedAt: current.updatedAtUnixMilliseconds)
        values[id] = value
        return value
    }

    func cancelDraft(
        id: String,
        expectedRevision _: UInt64,
        cancelledAtUnixMilliseconds: UInt64
    ) throws -> RadrootsDraftStatus {
        let current = try draftStatus(id: id)
        let value = replacing(current, revision: current.revision + 1, state: .cancelled, updatedAt: cancelledAtUnixMilliseconds)
        values[id] = value
        return value
    }

    func subscribe(
        bufferCapacity _: Int,
        receive _: @escaping @Sendable (RadrootsRuntimeChange) async -> Void
    ) -> any RadrootsRuntimeSubscriptionToken {
        AddSubscriptionToken()
    }

    func shutdown() -> RadrootsRuntimeShutdownReceipt {
        let wasClosed = closed
        closed = true
        return RadrootsRuntimeShutdownReceipt(state: "closed", alreadyClosed: wasClosed)
    }

    private func makeStatus(
        id: String,
        revision: UInt64,
        kind: RadrootsDraftKind,
        commandType: RadrootsAddCommandType,
        form: RadrootsAddForm?,
        state: RadrootsOutboxState,
        updatedAt: UInt64,
        media: [RadrootsDraftMediaStatus]
    ) -> RadrootsDraftStatus {
        RadrootsDraftStatus(
            id: id,
            revision: revision,
            authorPublicKey: String(repeating: "ab", count: 32),
            kind: kind,
            commandType: commandType,
            form: form,
            state: state,
            cardID: String(repeating: "c", count: 64),
            operationID: state == .draft ? nil : String(repeating: "d", count: 32),
            createdAtUnixMilliseconds: updatedAt,
            updatedAtUnixMilliseconds: updatedAt,
            media: media,
            settlement: state == .complete ? settlement() : nil
        )
    }

    private func replacing(
        _ value: RadrootsDraftStatus,
        revision: UInt64,
        state: RadrootsOutboxState,
        updatedAt: UInt64,
        media: [RadrootsDraftMediaStatus]? = nil
    ) -> RadrootsDraftStatus {
        RadrootsDraftStatus(
            id: value.id,
            revision: revision,
            authorPublicKey: value.authorPublicKey,
            kind: value.kind,
            commandType: value.commandType,
            form: value.form,
            state: state,
            cardID: value.cardID,
            operationID: state == .draft ? nil : String(repeating: "d", count: 32),
            createdAtUnixMilliseconds: value.createdAtUnixMilliseconds,
            updatedAtUnixMilliseconds: updatedAt,
            media: media ?? value.media,
            settlement: state == .complete ? settlement() : nil
        )
    }

    private func settlement() -> RadrootsOperationSettlement {
        RadrootsOperationSettlement(
            artifacts: 1,
            signed: 1,
            admitted: 1,
            pending: 0,
            retryable: 0,
            indeterminate: 0,
            failedTerminal: 0,
            cancelled: 0,
            deliveryPlans: 1,
            deliverySatisfied: 1,
            deliveryPending: 0,
            deliveryRetryable: 0,
            deliveryExhausted: 0,
            deliveryFailedTerminal: 0,
            deliveryCancelled: 0
        )
    }

    private func unsupported() -> RadrootsRuntimeFailure {
        .local(operation: "test.add", code: "test.unsupported", safeMessage: "Unsupported test operation.")
    }
}

private actor AddSubscriptionToken: RadrootsRuntimeSubscriptionToken {
    func cancel() {}
}
