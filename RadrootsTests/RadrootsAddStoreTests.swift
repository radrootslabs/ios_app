import XCTest

@testable import RadrootsApp

final class RadrootsAddStoreTests: XCTestCase {
  @MainActor
  func testAllFiveFormsCompleteThroughRuntimeAndSubmittedSnapshotsFreeze() async throws {
    let backend = AddBackend()
    let client = try await Self.startedClient(backend)
    let store = RadrootsAddStore(
      runtimeClient: client,
      media: AddMediaHarness()
    )
    await store.configure(snapshot: backend.snapshot())
    await store.start()

    for type in RadrootsAddCommandType.allCases {
      store.newDraft(type: type)
      configure(store, type: type)
      if type == .createPhotoUpdate {
        await store.importPhotos()
        XCTAssertEqual(store.form.media.count, 1)
        XCTAssertNil(store.form.media.first?.remoteURL)
      }
      await store.submit()
      XCTAssertEqual(store.activeDraft?.commandType, type)
      XCTAssertEqual(store.activeDraft?.state, .complete)
      XCTAssertEqual(store.activeDraft?.form, store.form)
      if type == .createPhotoUpdate {
        XCTAssertEqual(
          store.form.media.first?.remoteURL,
          "http://127.0.0.1:3000/\(String(repeating: "0", count: 64)).png"
        )
        let didUpload = await backend.didUploadMedia()
        XCTAssertTrue(didUpload)
      }
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
    let store = RadrootsAddStore(runtimeClient: client)
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
  func testRevisionUsesLosslessRustOwnedReplacementPlan() async throws {
    let backend = AddBackend(advanceOffline: true)
    let client = try await Self.startedClient(backend)
    let store = RadrootsAddStore(runtimeClient: client)
    await store.configure(snapshot: backend.snapshot())
    await store.start()
    store.selectType(.createFoodAvailability)
    configure(store, type: .createFoodAvailability)
    await store.save()
    let source = try XCTUnwrap(store.activeDraft)

    await store.retractAndRevise(Self.card(localOperationID: source.id))

    XCTAssertNil(store.activeDraft)
    XCTAssertEqual(store.form, source.form)
    store.updateForm(\.content, "Corrected harvest details")
    await store.submit()
    XCTAssertTrue(store.activeDraft?.isRevision == true)
    XCTAssertEqual(store.activeDraft?.state, .complete)
    let revisionPlanCount = await backend.revisionPlanCount()
    XCTAssertEqual(revisionPlanCount, 1)
    XCTAssertNil(store.drafts.first(where: { $0.kind == .retraction }))
    _ = try await client.stop()
  }

  @MainActor
  func testStopFencesSaveQueueAndAdvanceAndPermitsCleanRestart() async throws {
    for phase in AddDelayPhase.allCases {
      let backend = AddBackend(delayedPhase: phase)
      let client = try await Self.startedClient(backend)
      let store = RadrootsAddStore(runtimeClient: client)
      await store.configure(snapshot: backend.snapshot())
      await store.start()
      store.updateForm(\.content, "Restart after \(phase)")

      let submit = Task { await store.submit() }
      try await Task.sleep(nanoseconds: 2_000_000)
      let visibleAtStop = store.activeDraft
      store.stop()
      await submit.value

      XCTAssertEqual(store.activeDraft, visibleAtStop)
      XCTAssertFalse(store.isWorking)

      await store.start()
      XCTAssertEqual(store.state, .ready)
      if let durable = store.drafts.first {
        store.reopen(durable)
      }
      await store.submit()
      XCTAssertEqual(store.activeDraft?.state, .complete)
      XCTAssertFalse(store.isWorking)
      _ = try await client.stop()
    }
  }

  @MainActor
  func testStopDuringBackgroundUploadPermitsDurableRestart() async throws {
    let backend = AddBackend()
    let client = try await Self.startedClient(backend)
    let store = RadrootsAddStore(
      runtimeClient: client,
      media: AddMediaHarness(delayFirstUpload: true)
    )
    await store.configure(snapshot: backend.snapshot())
    await store.start()
    store.selectType(.createPhotoUpdate)
    store.updateForm(\.content, "Restart the background upload")
    await store.importPhotos()

    let submit = Task { await store.submit() }
    try await Task.sleep(nanoseconds: 2_000_000)
    let visibleAtStop = store.activeDraft
    store.stop()
    await submit.value

    XCTAssertEqual(store.activeDraft, visibleAtStop)
    XCTAssertFalse(store.isWorking)

    await store.start()
    let durable = try XCTUnwrap(store.drafts.first)
    XCTAssertEqual(durable.state, .mediaUploading)
    store.reopen(durable)
    await store.submit()
    XCTAssertEqual(store.activeDraft?.state, .complete)
    XCTAssertEqual(store.activeDraft?.media.first?.stage, .verified)
    _ = try await client.stop()
  }

  @MainActor
  func testPhotoServiceProbeSurfacesCanonicalEvidence() async throws {
    let backend = AddBackend()
    let client = try await Self.startedClient(backend)
    let store = RadrootsAddStore(runtimeClient: client, media: AddMediaHarness())
    await store.configure(snapshot: backend.snapshot())

    await store.checkPhotoService()

    XCTAssertEqual(store.blossomEvidence?.state, "reachable")
    XCTAssertEqual(store.blossomEvidence?.configFingerprint, String(repeating: "f", count: 64))
    XCTAssertEqual(store.mediaSupport, .init(library: true, camera: true))
    XCTAssertEqual(store.message, "Photo service is reachable.")
    _ = try await client.stop()
  }

  @MainActor
  func testPhotoLimitRejectsTwentyFirstImportAndCapture() async throws {
    let backend = AddBackend()
    let client = try await Self.startedClient(backend)
    let store = RadrootsAddStore(runtimeClient: client, media: AddMediaHarness())
    await store.configure(snapshot: backend.snapshot())
    await store.start()
    store.selectType(.createPhotoUpdate)

    for _ in 0..<20 {
      await store.importPhotos()
    }
    XCTAssertEqual(store.form.media.count, 20)
    XCTAssertFalse(store.canAddMedia)

    await store.importPhotos()
    await store.capturePhoto()
    XCTAssertEqual(store.form.media.count, 20)
    _ = try await client.stop()
  }

  @MainActor
  func testSuspendAndResumePreserveLateDurableDraftCompletion() async throws {
    let backend = AddBackend(delayedPhase: .save)
    let client = try await Self.startedClient(backend)
    let store = RadrootsAddStore(runtimeClient: client)
    await store.configure(snapshot: backend.snapshot())
    await store.start()
    store.updateForm(\.content, "Background draft")

    let save = Task { await store.save() }
    try await Task.sleep(nanoseconds: 2_000_000)
    store.suspend()
    await store.start()
    await save.value

    XCTAssertEqual(store.activeDraft?.form?.content, "Background draft")
    XCTAssertEqual(store.message, "Draft saved on this device.")
    XCTAssertFalse(store.isWorking)
    _ = try await client.stop()
  }

  @MainActor
  func testSubmitWithoutWritableRelayVerifiesMediaAndPreservesDraftForRetry() async throws {
    let backend = AddBackend(includeWritableRelay: false)
    let client = try await Self.startedClient(backend)
    let store = RadrootsAddStore(
      runtimeClient: client,
      media: AddMediaHarness()
    )
    await store.configure(snapshot: backend.snapshot())
    await store.start()
    store.selectType(.createPhotoUpdate)
    store.updateForm(\.content, "Carrots from today")
    await store.importPhotos()

    await store.submit()

    XCTAssertEqual(store.activeDraft?.state, .readyToSign)
    XCTAssertEqual(store.activeDraft?.media.first?.stage, .verified)
    XCTAssertEqual(
      store.message,
      "Photo verified and draft saved. Configure a writable relay to publish."
    )
    XCTAssertNil(store.lastFailureCode)
    _ = try await client.stop()
  }

  @MainActor
  func testSubmitRetainsRedactedFailureCodeForSupportAndAccessibility() async throws {
    let failure = RadrootsRuntimeFailure(
      schemaVersion: 1,
      code: "media_handle_unavailable",
      category: "validation",
      retryable: false,
      recoveryActions: [],
      operationID: "add.save",
      capabilityID: nil,
      safeMessage: "The request is invalid."
    )
    let backend = AddBackend(saveFailure: failure)
    let client = try await Self.startedClient(backend)
    let store = RadrootsAddStore(runtimeClient: client)
    await store.configure(snapshot: backend.snapshot())
    await store.start()
    store.updateForm(\.content, "Prepared media failure")

    await store.submit()

    XCTAssertEqual(store.message, failure.safeMessage)
    XCTAssertEqual(store.lastFailureCode, failure.code)
    XCTAssertNil(store.activeDraft)
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
      blossom: RadrootsBlossomEndpointConfiguration(
        hostKind: .simulator,
        endpointAuthority: .loopbackDevelopment,
        primaryOrigin: "http://127.0.0.1:3000",
        fallbackOrigins: []
      ),
      app: RadrootsRuntimeAppMetadata(
        bundleIdentifier: "org.radroots.add-tests",
        version: "0.1.0-alpha",
        buildNumber: "1",
        buildSHA: nil
      ),
      signerGeneration: "add-tests",
      signer: AddSigner(),
      adoptBootstrapSettings: false
    )
  }

  private static func card(localOperationID: String? = nil) -> RadrootsTodayCard {
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
      foodSummary: "Fresh carrots",
      foodPublishedAtUnixSeconds: 1_799_999_900,
      foodStatus: "active",
      contextRank: 1,
      inclusionReason: "local",
      media: [],
      lifecycle: .active,
      rankDigest: nil,
      authorProfile: nil,
      thread: [],
      localOperationID: localOperationID,
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
  private let delayFirstUpload: Bool
  private var uploadAttempts = 0
  private let item = RadrootsPreparedMedia(
    opaqueReference: "media:\(String(repeating: "0", count: 64))",
    remoteURL: nil,
    sha256: String(repeating: "0", count: 64),
    mediaType: "image/png",
    byteSize: 4,
    width: 2,
    height: 2,
    alt: "Carrots",
    preparedAtUnixSeconds: 1_800_000_000
  )

  init(delayFirstUpload: Bool = false) {
    self.delayFirstUpload = delayFirstUpload
  }

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

  func uploadInBackground(
    job: RadrootsNativeUploadJob,
    media _: RadrootsPreparedMedia
  ) async throws -> RadrootsAddBackgroundUploadReceipt {
    uploadAttempts += 1
    if delayFirstUpload, uploadAttempts == 1 {
      try await Task.sleep(nanoseconds: 50_000_000)
    }
    return RadrootsAddBackgroundUploadReceipt(
      identifier: "radroots.add.\(job.draft.id).\(job.draft.revision).\(job.operationID)",
      statusCode: 200,
      mediaType: "application/json",
      contentEncoding: nil,
      body: Data("{}".utf8)
    )
  }
}

private enum AddDelayPhase: String, CaseIterable {
  case save
  case queue
  case advance
}

private actor AddBackend: RadrootsRuntimeBackend {
  private let advanceOffline: Bool
  private let saveFailure: RadrootsRuntimeFailure?
  private let includeWritableRelay: Bool
  private let delayedPhase: AddDelayPhase?
  private var values: [String: RadrootsDraftStatus] = [:]
  private var uploadedMedia = false
  private var revisionPlans = 0
  private var delayConsumed = false
  private var closed = false

  init(
    advanceOffline: Bool = false,
    saveFailure: RadrootsRuntimeFailure? = nil,
    includeWritableRelay: Bool = true,
    delayedPhase: AddDelayPhase? = nil
  ) {
    self.advanceOffline = advanceOffline
    self.saveFailure = saveFailure
    self.includeWritableRelay = includeWritableRelay
    self.delayedPhase = delayedPhase
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
        relays: includeWritableRelay
          ? [
            RadrootsRelayEndpointStatus(
              url: "ws://127.0.0.1:7447",
              access: .readWrite,
              readState: "unobserved",
              writeState: "unobserved",
              readLastAttemptUnixMilliseconds: nil,
              writeLastAttemptUnixMilliseconds: nil,
              readNextAttemptUnixMilliseconds: nil,
              writeNextAttemptUnixMilliseconds: nil
            )
          ] : []
      ),
      blossomConfiguration: RadrootsBlossomConfigurationStatus(
        schemaVersion: 1,
        hostKind: "simulator",
        endpointAuthority: "loopback_development",
        primaryOrigin: "http://127.0.0.1:3000",
        fallbackOrigins: [],
        configFingerprint: String(repeating: "f", count: 64)
      ),
      blossomEvidence: nil,
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
    RadrootsAddCommandType.allCases.map { type in
      let maximum: UInt16? =
        switch type {
        case .createUpdate: nil
        case .createEvent: 1
        case .createPhotoUpdate, .createAsk, .createFoodAvailability: 20
        }
      return RadrootsAddSchema(
        schemaVersion: 1,
        commandType: type,
        label: type.label,
        fields: maximum.map {
          [
            RadrootsAddField(
              schemaVersion: 1,
              id: "media",
              label: "Photos",
              kind: .media,
              required: false,
              choices: [],
              maxBytes: 10 * 1024 * 1024,
              maxItems: $0
            )
          ]
        } ?? []
      )
    }
  }

  func saveAddIntent(
    input: RadrootsAddRuntimeInput,
    existingDraftID: String?,
    expectedRevision: UInt64?
  ) async throws -> RadrootsDraftStatus {
    if let saveFailure {
      throw saveFailure
    }
    try await delayOnce(at: .save)
    let id = existingDraftID ?? String(format: "%032x", values.count + 1)
    let savedMedia = input.form.media.map {
      RadrootsPreparedMedia(
        opaqueReference: $0.opaqueReference,
        remoteURL: "http://127.0.0.1:3000/\($0.sha256).png",
        sha256: $0.sha256,
        mediaType: $0.mediaType,
        byteSize: $0.byteSize,
        width: $0.width,
        height: $0.height,
        alt: $0.alt,
        preparedAtUnixSeconds: $0.preparedAtUnixSeconds
      )
    }
    var storedForm = input.form
    storedForm.media = savedMedia
    let status = makeStatus(
      id: id,
      revision: (expectedRevision ?? 0) + 1,
      kind: .add,
      commandType: input.form.commandType,
      form: storedForm,
      state: savedMedia.isEmpty ? .draft : .mediaPreparing,
      updatedAt: 1_800_000_000_000 + UInt64(values.count),
      media: savedMedia.map {
        RadrootsDraftMediaStatus(
          url: $0.remoteURL!,
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

  func probeBlossom() -> RadrootsBlossomEvidence {
    RadrootsBlossomEvidence(
      schemaVersion: 2,
      origin: "http://127.0.0.1:3000",
      configFingerprint: String(repeating: "f", count: 64),
      state: "reachable",
      lastSuccessfulState: "probe",
      transportSecurity: "loopback_plaintext",
      observedAtUnixMilliseconds: 1_800_000_000_000,
      httpStatus: 404,
      errorCode: nil,
      serverErrorCode: nil,
      errorPhase: nil,
      retryable: false,
      possibleOrphan: false,
      attempts: 1
    )
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

  func saveRevisionIntent(
    target: RadrootsRevisionTarget,
    replacement: RadrootsAddRuntimeInput
  ) -> RadrootsRevisionStatus {
    revisionPlans += 1
    let id = String(format: "%032x", values.count + 1)
    let status = makeStatus(
      id: id,
      revision: 1,
      kind: .add,
      commandType: replacement.form.commandType,
      form: replacement.form,
      state: replacement.form.media.isEmpty ? .draft : .mediaPreparing,
      updatedAt: 1_800_000_100_000,
      media: [],
      isRevision: true
    )
    values[id] = status
    return RadrootsRevisionStatus(
      operationID: id,
      replacement: status,
      retraction: nil,
      policy: target.sourceAddress == nil ? .replaceThenRetract : .addressableReplacement,
      phase: .replacementPending
    )
  }

  func revisionStatus(operationID: String) throws -> RadrootsRevisionStatus {
    let replacement = try draftStatus(id: operationID)
    return RadrootsRevisionStatus(
      operationID: operationID,
      replacement: replacement,
      retraction: nil,
      policy: .addressableReplacement,
      phase: replacement.state == .complete ? .complete : .replacementPending
    )
  }

  func advanceRevision(operationID: String) throws -> RadrootsRevisionStatus {
    let current = try draftStatus(id: operationID)
    let completed = replacing(
      current,
      revision: current.revision + 1,
      state: .complete,
      updatedAt: current.updatedAtUnixMilliseconds + 1
    )
    values[operationID] = completed
    return try revisionStatus(operationID: operationID)
  }

  func cancelRevision(operationID: String) throws -> RadrootsRevisionStatus {
    let current = try draftStatus(id: operationID)
    let cancelled = replacing(
      current,
      revision: current.revision + 1,
      state: .cancelled,
      updatedAt: current.updatedAtUnixMilliseconds + 1
    )
    values[operationID] = cancelled
    return RadrootsRevisionStatus(
      operationID: operationID,
      replacement: cancelled,
      retraction: nil,
      policy: .addressableReplacement,
      phase: .cancelled
    )
  }

  func draftStatus(id: String) throws -> RadrootsDraftStatus {
    try storedDraft(id: id)
  }

  func draftHeads(limit: UInt16) -> [RadrootsDraftStatus] {
    Array(values.values.prefix(Int(limit)))
  }

  func queueAddIntent(
    id: String,
    expectedRevision: UInt64
  ) async throws -> RadrootsDraftStatus {
    try await delayOnce(at: .queue)
    guard includeWritableRelay else {
      throw RadrootsRuntimeFailure(
        schemaVersion: 1,
        code: "writable_relay_unavailable",
        category: "relay",
        retryable: true,
        recoveryActions: ["configure_relay", "retry"],
        operationID: id,
        capabilityID: "nostr_sink",
        safeMessage: "No writable relay is configured."
      )
    }
    let current = try storedDraft(id: id)
    guard current.revision == expectedRevision else { throw unsupported() }
    let value = replacing(
      current, revision: current.revision + 1, state: .queued,
      updatedAt: current.updatedAtUnixMilliseconds + 1)
    values[id] = value
    return value
  }

  func recoverAddIntent(id: String) throws -> RadrootsDraftStatus {
    let current = try draftStatus(id: id)
    let value = replacing(
      current, revision: current.revision + 1, state: .queued,
      updatedAt: current.updatedAtUnixMilliseconds + 1)
    values[id] = value
    return value
  }

  func uploadAddMediaIntent(input: RadrootsBlossomUploadIntent) throws -> RadrootsDraftStatus {
    uploadedMedia = true
    let current = try draftStatus(id: input.draftID)
    let verified = current.media.map {
      RadrootsDraftMediaStatus(
        url: $0.url,
        stage: .verified,
        uploadAttempts: $0.uploadAttempts + 1,
        verifiedAtUnixMilliseconds: current.updatedAtUnixMilliseconds + 1,
        possibleOrphan: false,
        orphanReasonCode: nil,
        orphanRecordedAtUnixMilliseconds: nil
      )
    }
    let value = replacing(
      current,
      revision: current.revision + 1,
      state: .readyToSign,
      updatedAt: current.updatedAtUnixMilliseconds + 1,
      media: verified
    )
    values[current.id] = value
    return value
  }

  func prepareAddMediaBackground(
    input: RadrootsBlossomUploadIntent
  ) throws -> RadrootsNativeUploadJob {
    let current = try draftStatus(id: input.draftID)
    let uploading = replacing(
      current,
      revision: current.revision + 1,
      state: .mediaUploading,
      updatedAt: current.updatedAtUnixMilliseconds + 1
    )
    values[current.id] = uploading
    return RadrootsNativeUploadJob(
      operationID: String(repeating: "a", count: 32),
      draft: uploading,
      remoteURL: "http://127.0.0.1:3000/\(input.media.media.sha256).png",
      authorizationHeader: "Nostr test",
      expectedSHA256: input.media.media.sha256,
      mediaType: input.media.media.mediaType,
      byteSize: input.media.media.byteSize
    )
  }

  func completeAddMediaBackground(
    input: RadrootsNativeUploadCompletion
  ) throws -> RadrootsDraftStatus {
    uploadedMedia = true
    let current = try draftStatus(id: input.draftID)
    let verified = current.media.map {
      RadrootsDraftMediaStatus(
        url: $0.url,
        stage: .verified,
        uploadAttempts: $0.uploadAttempts + 1,
        verifiedAtUnixMilliseconds: current.updatedAtUnixMilliseconds + 1,
        possibleOrphan: false,
        orphanReasonCode: nil,
        orphanRecordedAtUnixMilliseconds: nil
      )
    }
    let value = replacing(
      current,
      revision: current.revision + 1,
      state: .readyToSign,
      updatedAt: current.updatedAtUnixMilliseconds + 1,
      media: verified
    )
    values[current.id] = value
    return value
  }

  func didUploadMedia() -> Bool {
    uploadedMedia
  }

  func revisionPlanCount() -> Int {
    revisionPlans
  }

  func advanceDraft(id: String, expectedRevision: UInt64) async throws -> RadrootsDraftStatus {
    try await delayOnce(at: .advance)
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
    let current = try storedDraft(id: id)
    let value = replacing(
      current, revision: expectedRevision, state: .complete,
      updatedAt: current.updatedAtUnixMilliseconds)
    values[id] = value
    return value
  }

  func cancelAddIntent(
    id: String,
    expectedRevision _: UInt64
  ) throws -> RadrootsDraftStatus {
    let current = try draftStatus(id: id)
    let value = replacing(
      current, revision: current.revision + 1, state: .cancelled,
      updatedAt: current.updatedAtUnixMilliseconds + 1)
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
    media: [RadrootsDraftMediaStatus],
    isRevision: Bool = false
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
      settlement: state == .complete ? settlement() : nil,
      isRevision: isRevision
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
      settlement: state == .complete ? settlement() : nil,
      isRevision: value.isRevision
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

  private func delayOnce(at phase: AddDelayPhase) async throws {
    guard delayedPhase == phase, !delayConsumed else { return }
    delayConsumed = true
    try await Task.sleep(nanoseconds: 50_000_000)
  }

  private func storedDraft(id: String) throws -> RadrootsDraftStatus {
    guard let value = values[id] else { throw unsupported() }
    return value
  }

  private func unsupported() -> RadrootsRuntimeFailure {
    .local(
      operation: "test.add", code: "test.unsupported", safeMessage: "Unsupported test operation.")
  }
}

private actor AddSubscriptionToken: RadrootsRuntimeSubscriptionToken {
  func cancel() {}
}
