import Foundation

enum RadrootsAddLoadState: Sendable, Equatable {
    case idle
    case loading
    case ready
    case failed(String)
}

@MainActor
final class RadrootsAddStore: ObservableObject {
    @Published private(set) var schemas: [RadrootsAddSchema] = []
    @Published private(set) var drafts: [RadrootsDraftStatus] = []
    @Published private(set) var activeDraft: RadrootsDraftStatus?
    @Published private(set) var form: RadrootsAddForm
    @Published private(set) var state: RadrootsAddLoadState = .idle
    @Published private(set) var mediaSupport: RadrootsAddMediaSupport = .unavailable
    @Published private(set) var isWorking = false
    @Published private(set) var message: String?

    private let runtimeClient: RadrootsRuntimeClient
    private let media: (any RadrootsAddMediaHandling)?
    private let now: @Sendable () -> UInt64
    private var writableRelays: [String] = []
    private var generation: UInt64 = 0
    private var operationGeneration: UInt64?
    private var observationTask: Task<Void, Never>?
    private var isStarted = false

    init(
        runtimeClient: RadrootsRuntimeClient,
        media: (any RadrootsAddMediaHandling)? = nil,
        initialType: RadrootsAddCommandType = .createUpdate,
        now: @escaping @Sendable () -> UInt64 = {
            UInt64(Date().timeIntervalSince1970)
        }
    ) {
        self.runtimeClient = runtimeClient
        self.media = media
        self.now = now
        form = .empty(initialType)
    }

    deinit {
        observationTask?.cancel()
    }

    var selectedSchema: RadrootsAddSchema? {
        schemas.first(where: { $0.commandType == form.commandType })
    }

    var isFormEditable: Bool {
        activeDraft?.state.isEditable ?? true
    }

    var canSave: Bool {
        isFormEditable && !isWorking
    }

    var canSubmit: Bool {
        !isWorking && (activeDraft?.state.canAdvance == true || isFormEditable)
    }

    func configure(snapshot: RadrootsRuntimeSnapshot) {
        writableRelays = snapshot.relay?.relays
            .filter { $0.access != "read_only" }
            .map(\.url) ?? []
    }

    func start() async {
        guard !isStarted else { return }
        isStarted = true
        state = .loading
        generation &+= 1
        let requestedGeneration = generation
        observationTask = Task { [weak self, runtimeClient] in
            do {
                let changes = try await runtimeClient.changes(bufferCapacity: 16)
                for await change in changes {
                    guard !Task.isCancelled else { break }
                    if change.kind == .drafts || change.kind == .media {
                        await self?.reloadDrafts()
                    }
                }
            } catch {
                // Durable draft operations remain available without observation.
            }
        }
        do {
            async let schemaResult = runtimeClient.addSchemas()
            async let draftResult = runtimeClient.draftHeads(limit: 100)
            async let supportResult = loadMediaSupport()
            let (loadedSchemas, loadedDrafts, loadedSupport) = try await (
                schemaResult,
                draftResult,
                supportResult
            )
            guard requestedGeneration == generation else { return }
            schemas = loadedSchemas
            drafts = Self.sorted(loadedDrafts)
            mediaSupport = loadedSupport
            state = .ready
        } catch {
            guard requestedGeneration == generation else { return }
            state = .failed(Self.message(for: error))
        }
    }

    func stop() {
        generation &+= 1
        isStarted = false
        observationTask?.cancel()
        observationTask = nil
        isWorking = false
    }

    func selectType(_ type: RadrootsAddCommandType) {
        guard !isWorking, isFormEditable, form.commandType != type else { return }
        activeDraft = nil
        form = .empty(type)
        message = nil
    }

    func updateForm<Value>(_ keyPath: WritableKeyPath<RadrootsAddForm, Value>, _ value: Value) {
        guard isFormEditable else { return }
        form[keyPath: keyPath] = value
    }

    func newDraft(type: RadrootsAddCommandType? = nil) {
        guard !isWorking else { return }
        generation &+= 1
        activeDraft = nil
        form = .empty(type ?? form.commandType)
        message = nil
    }

    func reopen(_ draft: RadrootsDraftStatus) {
        guard !isWorking else { return }
        guard let snapshot = draft.form else {
            message = "This operation has no editable Add form."
            return
        }
        generation &+= 1
        activeDraft = draft
        form = snapshot
        message = draft.state.isEditable ? "Draft reopened." : draft.honestSummary
    }

    func importPhotos() async {
        guard isFormEditable, form.commandType.acceptsMedia, let media else {
            message = "Photo intake is unavailable."
            return
        }
        await perform {
            let remaining = max(1, 20 - self.form.media.count)
            let imported = try await media.importImages(limit: remaining)
            self.form.media.append(contentsOf: imported)
            self.message = "Photo prepared. Add descriptive text before publishing."
        }
    }

    func capturePhoto() async {
        guard isFormEditable, form.commandType.acceptsMedia, let media else {
            message = "Camera intake is unavailable."
            return
        }
        await perform {
            try await self.form.media.append(media.captureImage())
            self.message = "Photo prepared. Add descriptive text before publishing."
        }
    }

    func removeMedia(id: String) {
        guard isFormEditable else { return }
        form.media.removeAll(where: { $0.id == id })
    }

    func updateMediaAlt(id: String, alt: String) {
        guard isFormEditable,
              let index = form.media.firstIndex(where: { $0.id == id })
        else { return }
        form.media[index].alt = alt
    }

    func save() async {
        await perform {
            _ = try await self.saveCurrentForm()
            self.message = "Draft saved on this device."
        }
    }

    func submit() async {
        await perform {
            var status: RadrootsDraftStatus = if let active = self.activeDraft, !active.state.isEditable {
                active
            } else {
                try await self.saveCurrentForm()
            }

            if !status.media.isEmpty,
               status.media.contains(where: { $0.stage != .verified })
            {
                status = try await self.uploadPendingMedia(status)
            }

            if status.state.isEditable || status.state == .readyToSign {
                status = try await self.runtimeClient.queueDraft(
                    id: status.id,
                    expectedRevision: status.revision,
                    policy: self.queuePolicy(),
                    queuedAtUnixMilliseconds: self.nowMilliseconds()
                )
                self.accept(status)
            }

            do {
                if status.state.canAdvance {
                    status = try await self.runtimeClient.advanceDraft(
                        id: status.id,
                        expectedRevision: status.revision
                    )
                    self.accept(status)
                }
                self.message = status.honestSummary
            } catch {
                // Queueing is the commit point. A later retry must reuse this immutable snapshot.
                self.message = "Saved for retry. \(Self.message(for: error))"
            }
        }
    }

    func retry(_ draft: RadrootsDraftStatus? = nil) async {
        guard let draft = draft ?? activeDraft else { return }
        await perform {
            var current = try await self.runtimeClient.draftStatus(id: draft.id)
            if current.state == .draft || current.state == .mediaPreparing || current.state == .readyToSign {
                self.activeDraft = current
                if let form = current.form {
                    self.form = form
                }
                self.message = "Review the draft before submitting again."
                return
            }
            if current.state.canAdvance {
                current = try await self.runtimeClient.advanceDraft(
                    id: current.id,
                    expectedRevision: current.revision
                )
            }
            self.accept(current)
            self.message = current.honestSummary
        }
    }

    func cancel(_ draft: RadrootsDraftStatus? = nil) async {
        guard let draft = draft ?? activeDraft, draft.state.canCancel else { return }
        await perform {
            let current = try await self.runtimeClient.draftStatus(id: draft.id)
            let cancelled = try await self.runtimeClient.cancelDraft(
                id: current.id,
                expectedRevision: current.revision,
                cancelledAtUnixMilliseconds: self.nowMilliseconds()
            )
            self.accept(cancelled)
            self.message = "Local work was cancelled. Any already-published relay effect is preserved."
        }
    }

    func retractAndRevise(_ card: RadrootsTodayCard) async {
        await perform {
            let retractionID = Self.draftID()
            var retraction = try await self.runtimeClient.saveRetractionDraft(
                id: retractionID,
                input: Self.retractionInput(card),
                authoredAtUnixSeconds: self.now(),
                persistedAtUnixMilliseconds: self.nowMilliseconds()
            )
            retraction = try await self.runtimeClient.queueDraft(
                id: retraction.id,
                expectedRevision: retraction.revision,
                policy: self.queuePolicy(),
                queuedAtUnixMilliseconds: self.nowMilliseconds()
            )
            self.accept(retraction)
            do {
                retraction = try await self.runtimeClient.advanceDraft(
                    id: retraction.id,
                    expectedRevision: retraction.revision
                )
                self.accept(retraction)
            } catch {
                self.message = "The retraction is saved for retry. The revised copy remains separate."
            }
            self.activeDraft = nil
            self.form = Self.revisedForm(card)
            self.message = "Retraction: \(retraction.honestSummary). Review the separate revised copy before publishing."
        }
    }

    private func saveCurrentForm() async throws -> RadrootsDraftStatus {
        guard isFormEditable else {
            throw RadrootsRuntimeFailure.local(
                operation: "add.save",
                code: "ios.add.form_frozen",
                safeMessage: "Submitted drafts cannot be changed. Create a revised copy instead."
            )
        }
        let id = activeDraft?.id ?? Self.draftID()
        let opened = try await openedMedia()
        defer { opened.close() }
        let status = try await runtimeClient.saveDraft(
            id: id,
            input: RadrootsAddRuntimeInput(form: form, media: opened.handles),
            authoredAtUnixSeconds: now(),
            expectedRevision: activeDraft?.revision,
            persistedAtUnixMilliseconds: nowMilliseconds()
        )
        accept(status)
        return status
    }

    private func uploadPendingMedia(_ initial: RadrootsDraftStatus) async throws -> RadrootsDraftStatus {
        var status = initial
        guard let form = status.form else { return status }
        let opened = try await openedMedia(form.media)
        defer { opened.close() }
        for mediaStatus in status.media where mediaStatus.stage != .verified {
            guard let handle = opened.handles.first(where: { $0.media.url == mediaStatus.url }) else {
                throw RadrootsRuntimeFailure.local(
                    operation: "add.media.upload",
                    code: "ios.add.media_missing",
                    safeMessage: "A prepared photo is unavailable."
                )
            }
            let currentSeconds = now()
            status = try await runtimeClient.uploadDraftMedia(
                input: RadrootsBlossomUploadInput(
                    draftID: status.id,
                    expectedRevision: status.revision,
                    media: handle,
                    authorizationContent: "Upload exact Radroots image",
                    authorizationCreatedAtUnixSeconds: currentSeconds,
                    authorizationLifetimeSeconds: 300,
                    operationID: Self.draftID(),
                    artifactID: Self.draftID(),
                    signingDeadlineUnixMilliseconds: nowMilliseconds() + 60000,
                    signingCancellation: .localCooperative,
                    verifiedAtUnixMilliseconds: nowMilliseconds(),
                    updatedAtUnixMilliseconds: nowMilliseconds()
                )
            )
            accept(status)
        }
        return status
    }

    private func openedMedia(_ values: [RadrootsPreparedMedia]? = nil) async throws -> RadrootsOpenedMedia {
        let values = values ?? form.media
        guard !values.isEmpty else { return RadrootsOpenedMedia(handles: [], files: []) }
        guard let media else {
            throw RadrootsRuntimeFailure.local(
                operation: "add.media.open",
                code: "ios.add.media_unavailable",
                safeMessage: "Prepared photos are unavailable on this device."
            )
        }
        return try await media.open(values)
    }

    private func queuePolicy() -> RadrootsQueuePolicy {
        RadrootsQueuePolicy(
            relayURLs: writableRelays,
            satisfaction: .allAccepted,
            deliveryDeadlineUnixMilliseconds: nowMilliseconds() + 24 * 60 * 60 * 1000,
            cancellation: .localCooperative
        )
    }

    private func reloadDrafts() async {
        do {
            let loaded = try await runtimeClient.draftHeads(limit: 100)
            drafts = Self.sorted(loaded)
            if let activeDraft,
               let current = loaded.first(where: { $0.id == activeDraft.id })
            {
                self.activeDraft = current
            }
        } catch {
            message = Self.message(for: error)
        }
    }

    private func loadMediaSupport() async throws -> RadrootsAddMediaSupport {
        guard let media else { return .unavailable }
        return try await media.support()
    }

    private func accept(_ status: RadrootsDraftStatus) {
        guard operationGeneration == nil || operationGeneration == generation else { return }
        activeDraft = status
        if let form = status.form {
            self.form = form
        }
        drafts.removeAll(where: { $0.id == status.id })
        drafts.append(status)
        drafts = Self.sorted(drafts)
    }

    private func perform(_ operation: @escaping () async throws -> Void) async {
        generation &+= 1
        let requestedGeneration = generation
        operationGeneration = requestedGeneration
        isWorking = true
        message = nil
        do {
            try await operation()
        } catch is CancellationError {
            if requestedGeneration == generation {
                message = "The operation was cancelled."
            }
        } catch {
            if requestedGeneration == generation {
                message = Self.message(for: error)
            }
        }
        if requestedGeneration == generation {
            isWorking = false
            operationGeneration = nil
        }
    }

    private func nowMilliseconds() -> UInt64 {
        now() * 1000
    }

    private static func sorted(_ drafts: [RadrootsDraftStatus]) -> [RadrootsDraftStatus] {
        drafts.sorted {
            if $0.updatedAtUnixMilliseconds == $1.updatedAtUnixMilliseconds {
                return $0.id < $1.id
            }
            return $0.updatedAtUnixMilliseconds > $1.updatedAtUnixMilliseconds
        }
    }

    private static func draftID() -> String {
        UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
    }

    private static func message(for error: Error) -> String {
        if case let RadrootsRuntimeClientError.add(failure) = error {
            return failure.safeMessage
        }
        if let failure = error as? RadrootsRuntimeFailure {
            return failure.safeMessage
        }
        return (error as? LocalizedError)?.errorDescription ?? "The Add operation could not be completed."
    }

    private static func retractionInput(_ card: RadrootsTodayCard) -> RadrootsRetractionDraftInput {
        let command = commandType(for: card.type)
        let kind: UInt32 = switch card.type {
        case .update, .photoUpdate, .ask: 1
        case .event: card.contractID == "radroots.calendar.date_event.v1" ? 31922 : 31923
        case .foodAvailability: 30402
        }
        return RadrootsRetractionDraftInput(
            commandType: command,
            targetCardID: card.id,
            targetEventID: card.sourceEventID,
            targetKind: kind,
            targetAddress: card.sourceAddress,
            reason: "Replaced with a revised copy"
        )
    }

    private static func revisedForm(_ card: RadrootsTodayCard) -> RadrootsAddForm {
        let command = commandType(for: card.type)
        var form = RadrootsAddForm.empty(command)
        form.content = card.content
        form.title = card.title
        form.location = card.location
        form.priceAmount = card.priceAmount
        form.currency = card.priceCurrency
        form.unit = card.priceUnit
        form.quantity = card.quantity
        if let address = card.sourceAddress?.split(separator: ":").last {
            form.identifier = String(address)
        }
        if command == .createEvent {
            form.eventTiming = card.contractID == "radroots.calendar.date_event.v1" ? .allDay : .timed
            if form.eventTiming == .timed {
                form.eventStartUnixSeconds = card.eventStartUnixSeconds
                form.eventEndUnixSeconds = card.eventEndUnixSeconds
                form.eventTimezone = TimeZone.current.identifier
            } else if let start = card.eventStartUnixSeconds {
                form.eventStartDate = dateString(start)
                form.eventEndDate = card.eventEndUnixSeconds.map(dateString)
            }
        }
        return form
    }

    private static func dateString(_ seconds: UInt64) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date(timeIntervalSince1970: TimeInterval(seconds)))
    }

    private static func commandType(for card: RadrootsTodayCardType) -> RadrootsAddCommandType {
        switch card {
        case .update: .createUpdate
        case .photoUpdate: .createPhotoUpdate
        case .ask: .createAsk
        case .event: .createEvent
        case .foodAvailability: .createFoodAvailability
        }
    }
}
