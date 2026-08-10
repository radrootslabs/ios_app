import Foundation
import RadrootsKitBindings

private final class RadrootsGeneratedHostSigner: RadrootsHostSigner, @unchecked Sendable {
    private let signer: any RadrootsRuntimeSigner

    init(signer: any RadrootsRuntimeSigner) {
        self.signer = signer
    }

    func signerStatus() async -> SignerStatusRecord {
        await SignerStatusRecord(
            schemaVersion: 1,
            availability: signer.availability().generatedValue
        )
    }

    func sign(request: HostSigningRequest) async -> HostSigningResult {
        let purpose = request.purpose.appValue
        let outcome = await signer.sign(
            RadrootsRuntimeSigningRequest(
                operationID: request.operationId,
                signerRequestID: request.signerRequestId,
                publicKeyHex: request.publicKey,
                purpose: purpose,
                deadlineUnixMilliseconds: request.deadlineUnixMs,
                digest: request.eventIdDigest
            )
        )
        #if DEBUG
            if request.purpose == .blossomUpload,
               let signatureHex = outcome.signatureHex
            {
                try? RadrootsRemoteQualificationEvidence.recordBlossomAuthorization(
                    request: request,
                    signatureHex: signatureHex
                )
            }
        #endif
        return HostSigningResult(
            schemaVersion: 1,
            outcome: outcome.generatedOutcome,
            operationId: request.operationId,
            signerRequestId: request.signerRequestId,
            publicKey: request.publicKey,
            purpose: request.purpose,
            signatureHex: outcome.signatureHex,
            completedAtUnixMs: UInt64(Date().timeIntervalSince1970 * 1000)
        )
    }
}

private final class RadrootsGeneratedRuntimeObserver: RadrootsRuntimeObserver, @unchecked Sendable {
    private let continuation: AsyncStream<RadrootsRuntimeChange>.Continuation

    init(continuation: AsyncStream<RadrootsRuntimeChange>.Continuation) {
        self.continuation = continuation
    }

    func onChange(change: FfiRuntimeChangeRecord) {
        continuation.yield(
            RadrootsRuntimeChange(
                schemaVersion: change.schemaVersion,
                generation: change.generation,
                kind: change.kind.appValue,
                entityID: change.entityId
            )
        )
    }

    func finish() {
        continuation.finish()
    }
}

private actor RadrootsGeneratedSubscriptionToken: RadrootsRuntimeSubscriptionToken {
    private var handle: FfiSubscriptionHandle?
    private var observer: RadrootsGeneratedRuntimeObserver?
    private var deliveryTask: Task<Void, Never>?

    init(
        handle: FfiSubscriptionHandle,
        observer: RadrootsGeneratedRuntimeObserver,
        deliveryTask: Task<Void, Never>
    ) {
        self.handle = handle
        self.observer = observer
        self.deliveryTask = deliveryTask
    }

    func cancel() async {
        guard let handle else { return }
        self.handle = nil
        observer?.finish()
        observer = nil
        handle.unsubscribe()
        deliveryTask?.cancel()
        await deliveryTask?.value
        deliveryTask = nil
    }
}

private final class RadrootsGeneratedRuntimeBackend: RadrootsRuntimeBackend, @unchecked Sendable {
    private let runtime: RadrootsRuntime

    init(runtime: RadrootsRuntime) {
        self.runtime = runtime
    }

    func snapshot() async throws -> RadrootsRuntimeSnapshot {
        do {
            let identity = try runtime.identityStatus()
            let relay = try runtime.sdkRelayStatus()
            let blossomConfiguration = try runtime.sdkBlossomConfiguration()
            let blossomEvidence = try runtime.sdkBlossomEvidence()
            let info = runtime.info()
            return RadrootsRuntimeSnapshot(
                identity: RadrootsRuntimeIdentity(
                    publicKeyHex: identity.publicKey,
                    hostSignerConfigured: identity.hostSignerConfigured
                ),
                relay: relay.map { report in
                    RadrootsRelayStatus(
                        profile: report.profile,
                        state: report.state,
                        readAvailability: report.readAvailability,
                        writeAvailability: report.writeAvailability,
                        relays: report.relays.map { relay in
                            RadrootsRelayEndpointStatus(
                                url: relay.relayUrl,
                                access: relay.access,
                                readState: relay.readState,
                                writeState: relay.writeState,
                                readLastAttemptUnixMilliseconds: relay.readLastAttemptUnixMs,
                                writeLastAttemptUnixMilliseconds: relay.writeLastAttemptUnixMs,
                                readNextAttemptUnixMilliseconds: relay.readNextAttemptUnixMs,
                                writeNextAttemptUnixMilliseconds: relay.writeNextAttemptUnixMs
                            )
                        }
                    )
                },
                blossomConfiguration: blossomConfiguration?.appValue,
                blossomEvidence: blossomEvidence?.appValue,
                crateName: info.sdk.crateName,
                crateVersion: info.sdk.crateVersion,
                isClosed: info.sdkClosed
            )
        } catch {
            throw Self.failure(from: error)
        }
    }

    func todayPage(request: RadrootsTodayPageRequest) async throws -> RadrootsTodayPage {
        do {
            let page = try await runtime.phase1TodayPage(
                context: request.context.generatedValue,
                limit: request.limit,
                asOfUnixS: request.asOfUnixSeconds,
                cursor: request.cursor
            )
            return page.appValue
        } catch {
            throw Self.failure(from: error)
        }
    }

    func refreshToday(
        context: RadrootsLocalNetwork,
        nowUnixSeconds: UInt64,
        update: RadrootsTodayProjectionUpdate
    ) async throws -> RadrootsTodayRefreshReceipt {
        do {
            let receipt = try await runtime.phase1SyncToday(
                context: context.generatedValue,
                nowUnixS: nowUnixSeconds,
                update: update.generatedValue
            )
            switch receipt.relayState {
            case .complete:
                return receipt.projection.appValue
            case .partial:
                throw RadrootsRuntimeFailure(
                    schemaVersion: 1,
                    code: "today_relay_partial",
                    category: "relay",
                    retryable: true,
                    recoveryActions: ["retry"],
                    operationID: "runtime.today.refresh",
                    capabilityID: "nostr_source",
                    safeMessage: "Today refreshed from only part of the local network."
                )
            case .offline:
                throw RadrootsRuntimeFailure(
                    schemaVersion: 1,
                    code: "today_relay_offline",
                    category: "relay",
                    retryable: true,
                    recoveryActions: ["retry"],
                    operationID: "runtime.today.refresh",
                    capabilityID: "nostr_source",
                    safeMessage: "Today is showing saved posts because the local network is offline."
                )
            }
        } catch {
            throw Self.failure(from: error)
        }
    }

    func search(
        context: RadrootsLocalNetwork,
        query: String,
        limit: UInt16,
        asOfUnixSeconds: UInt64
    ) async throws -> [RadrootsSearchResult] {
        do {
            return try await runtime.phase1Search(
                context: context.generatedValue,
                query: query,
                limit: limit,
                asOfUnixS: asOfUnixSeconds
            ).map(\.appValue)
        } catch {
            throw Self.failure(from: error)
        }
    }

    func me(
        context: RadrootsLocalNetwork,
        asOfUnixSeconds: UInt64
    ) async throws -> RadrootsMeSnapshot {
        do {
            return try await runtime.phase1Me(
                context: context.generatedValue,
                asOfUnixS: asOfUnixSeconds
            ).appValue
        } catch {
            throw Self.failure(from: error)
        }
    }

    func addSchemas() async throws -> [RadrootsAddSchema] {
        runtime.phase1AddSchemas().map(\.appValue)
    }

    func saveAddIntent(
        input: RadrootsAddRuntimeInput,
        existingDraftID: String?,
        expectedRevision: UInt64?
    ) async throws -> RadrootsDraftStatus {
        do {
            return try await runtime.phase1SaveAddIntent(
                input: input.generatedValue,
                existingDraftId: existingDraftID,
                expectedRevision: expectedRevision
            ).appValue
        } catch {
            throw Self.failure(from: error)
        }
    }

    func saveRetractionDraft(
        id: String,
        input: RadrootsRetractionDraftInput,
        authoredAtUnixSeconds: UInt64,
        persistedAtUnixMilliseconds: UInt64
    ) async throws -> RadrootsDraftStatus {
        do {
            return try await runtime.phase1SaveRetractionDraft(
                draftId: id,
                input: input.generatedValue,
                authoredAtUnixS: authoredAtUnixSeconds,
                persistedAtUnixMs: persistedAtUnixMilliseconds
            ).appValue
        } catch {
            throw Self.failure(from: error)
        }
    }

    func draftStatus(id: String) async throws -> RadrootsDraftStatus {
        do {
            return try await runtime.phase1DraftStatus(draftId: id).appValue
        } catch {
            throw Self.failure(from: error)
        }
    }

    func draftHeads(limit: UInt16) async throws -> [RadrootsDraftStatus] {
        do {
            return try await runtime.phase1DraftHeads(limit: limit).map(\.appValue)
        } catch {
            throw Self.failure(from: error)
        }
    }

    func queueAddIntent(
        id: String,
        expectedRevision: UInt64
    ) async throws -> RadrootsDraftStatus {
        do {
            return try await runtime.phase1QueueAddIntent(
                draftId: id,
                expectedRevision: expectedRevision
            ).appValue
        } catch {
            throw Self.failure(from: error)
        }
    }

    func recoverAddIntent(id: String) async throws -> RadrootsDraftStatus {
        do {
            return try await runtime.phase1RecoverAddIntent(draftId: id).appValue
        } catch {
            throw Self.failure(from: error)
        }
    }

    func uploadAddMediaIntent(input: RadrootsBlossomUploadIntent) async throws -> RadrootsDraftStatus {
        do {
            return try await runtime.phase1UploadAddMediaIntent(input: input.generatedValue).appValue
        } catch {
            throw Self.failure(from: error)
        }
    }

    func probeBlossom() async throws -> RadrootsBlossomEvidence {
        do {
            return try await runtime.probeBlossom().appValue
        } catch {
            throw Self.failure(from: error)
        }
    }

    func advanceDraft(id: String, expectedRevision: UInt64) async throws -> RadrootsDraftStatus {
        do {
            return try await runtime.phase1AdvanceDraft(
                draftId: id,
                expectedRevision: expectedRevision
            ).appValue
        } catch {
            throw Self.failure(from: error)
        }
    }

    func cancelAddIntent(
        id: String,
        expectedRevision: UInt64
    ) async throws -> RadrootsDraftStatus {
        do {
            return try await runtime.phase1CancelAddIntent(
                draftId: id,
                expectedRevision: expectedRevision
            ).appValue
        } catch {
            throw Self.failure(from: error)
        }
    }

    func subscribe(
        bufferCapacity: Int,
        receive: @escaping @Sendable (RadrootsRuntimeChange) async -> Void
    ) async throws -> any RadrootsRuntimeSubscriptionToken {
        let pair = AsyncStream.makeStream(
            of: RadrootsRuntimeChange.self,
            bufferingPolicy: .bufferingNewest(bufferCapacity)
        )
        do {
            let observer = RadrootsGeneratedRuntimeObserver(continuation: pair.continuation)
            let handle = try runtime.subscribeChanges(observer: observer)
            let deliveryTask = Task {
                for await change in pair.stream {
                    guard !Task.isCancelled else { break }
                    await receive(change)
                }
            }
            return RadrootsGeneratedSubscriptionToken(
                handle: handle,
                observer: observer,
                deliveryTask: deliveryTask
            )
        } catch {
            pair.continuation.finish()
            throw Self.failure(from: error)
        }
    }

    func shutdown() async throws -> RadrootsRuntimeShutdownReceipt {
        do {
            let receipt = try await runtime.shutdown()
            return RadrootsRuntimeShutdownReceipt(
                state: receipt.state,
                alreadyClosed: receipt.alreadyClosed
            )
        } catch {
            throw Self.failure(from: error)
        }
    }

    static func start(
        configuration: RadrootsRuntimeLaunchConfiguration
    ) async throws -> RadrootsRuntimeBackendStart {
        var createdRuntime: RadrootsRuntime?
        do {
            let runtime = try await RadrootsRuntime.withHostSigner(
                applicationSupportDirectory: configuration.applicationSupportDirectory,
                publicKeyHex: configuration.publicKeyHex,
                sourceGenerationHex: configuration.sourceGenerationHex,
                sourceGenerationCreatedAtUnixMs: configuration.sourceGenerationCreatedAtUnixMilliseconds,
                protectedData: configuration.protectedData.generatedValue,
                hostSigner: RadrootsGeneratedHostSigner(signer: configuration.signer)
            )
            createdRuntime = runtime
            runtime.setAppInfoPlatform(
                platform: "iOS",
                bundleId: configuration.app.bundleIdentifier,
                version: configuration.app.version,
                buildNumber: configuration.app.buildNumber,
                buildSha: configuration.app.buildSHA
            )

            switch configuration.networkProfile {
            case .publicNetwork:
                try runtime.configurePublicRelays(writableRelays: configuration.writableRelays)
            case .simulator:
                try runtime.configureSimulatorRelays(loopbackRelays: configuration.writableRelays)
            case .device:
                try runtime.configureDeviceRelays(writableRelays: configuration.writableRelays)
            }
            if let blossom = configuration.blossom {
                try runtime.configureBlossom(
                    hostKind: blossom.hostKind.generatedValue,
                    endpointAuthority: blossom.endpointAuthority.generatedValue,
                    primaryOrigin: blossom.primaryOrigin,
                    fallbackOrigins: blossom.fallbackOrigins
                )
            }

            let backend = RadrootsGeneratedRuntimeBackend(runtime: runtime)
            return try await RadrootsRuntimeBackendStart(
                backend: backend,
                snapshot: backend.snapshot()
            )
        } catch {
            if let createdRuntime {
                _ = try? await createdRuntime.shutdown()
            }
            throw Self.failure(from: error)
        }
    }

    private static func failure(from error: Error) -> RadrootsRuntimeFailure {
        if case let RadrootsAppError.Failure(report) = error {
            return RadrootsRuntimeFailure(
                schemaVersion: report.schemaVersion,
                code: report.code,
                category: report.category,
                retryable: report.retryable,
                recoveryActions: report.recoveryActions,
                operationID: report.operationId,
                capabilityID: report.capabilityId,
                safeMessage: report.safeMessage
            )
        }
        if let failure = error as? RadrootsRuntimeFailure {
            return failure
        }
        return .local(
            operation: "generated.runtime",
            code: "ios.generated_runtime.unexpected",
            safeMessage: "The Radroots runtime could not complete the operation."
        )
    }
}

private extension RadrootsRuntimeSignerAvailability {
    var generatedValue: SignerAvailabilityRecord {
        switch self {
        case .ready: .ready
        case .busy: .busy
        case .locked: .locked
        case .unavailable: .unavailable
        }
    }
}

private extension HostSigningPurpose {
    var appValue: RadrootsRuntimeSigningPurpose {
        switch self {
        case .nostrEvent: .nostrEvent
        case .blossomUpload: .blossomUpload
        }
    }
}

private extension RadrootsRuntimeSigningOutcome {
    var generatedOutcome: HostSigningOutcome {
        switch self {
        case .signed: .signed
        case .locked: .locked
        case .cancelled: .cancelled
        case .rejected: .rejected
        case .timedOut: .timedOut
        case .unavailable: .unavailable
        case .invalidated: .invalidated
        case .failed: .failed
        }
    }

    var signatureHex: String? {
        if case let .signed(signatureHex) = self {
            return signatureHex
        }
        return nil
    }
}

extension RadrootsRuntimeClient {
    static func production() -> RadrootsRuntimeClient {
        RadrootsRuntimeClient { configuration in
            try await RadrootsGeneratedRuntimeBackend.start(configuration: configuration)
        }
    }
}

private extension RadrootsProtectedDataState {
    var generatedValue: ProtectedDataAvailability {
        switch self {
        case .available: .available
        case .unavailable: .unavailable
        }
    }
}

private extension RadrootsBlossomHostKind {
    var generatedValue: FfiBlossomHostKind {
        switch self {
        case .native: .native
        case .simulator: .simulator
        case .physicalDevice: .physicalDevice
        }
    }
}

private extension RadrootsBlossomEndpointAuthority {
    var generatedValue: FfiBlossomEndpointAuthority {
        switch self {
        case .publicWebPKI: .publicWebPki
        case .loopbackDevelopment: .loopbackDevelopment
        case .privateNetworkDevelopment: .privateNetworkDevelopment
        }
    }
}

private extension FfiBlossomConfigurationRecord {
    var appValue: RadrootsBlossomConfigurationStatus {
        RadrootsBlossomConfigurationStatus(
            schemaVersion: schemaVersion,
            hostKind: hostKind,
            endpointAuthority: endpointAuthority,
            primaryOrigin: primaryOrigin,
            fallbackOrigins: fallbackOrigins,
            configFingerprint: configFingerprint
        )
    }
}

private extension FfiBlossomEvidenceRecord {
    var appValue: RadrootsBlossomEvidence {
        RadrootsBlossomEvidence(
            schemaVersion: schemaVersion,
            origin: origin,
            configFingerprint: configFingerprint,
            state: state,
            lastSuccessfulState: lastSuccessfulState,
            transportSecurity: transportSecurity,
            observedAtUnixMilliseconds: observedAtUnixMs,
            httpStatus: httpStatus,
            errorCode: errorCode,
            serverErrorCode: serverErrorCode,
            errorPhase: errorPhase,
            retryable: retryable,
            possibleOrphan: possibleOrphan,
            attempts: attempts
        )
    }
}

private extension FfiRuntimeChangeKind {
    var appValue: RadrootsRuntimeChangeKind {
        switch self {
        case .initial: .initial
        case .identity: .identity
        case .settings: .settings
        case .profile: .profile
        case .today: .today
        case .drafts: .drafts
        case .relay: .relay
        case .media: .media
        case .lifecycle: .lifecycle
        }
    }
}

private extension RadrootsLocalNetwork {
    var generatedValue: FfiLocalNetworkRecord {
        FfiLocalNetworkRecord(
            schemaVersion: schemaVersion,
            id: id,
            label: label,
            relayUrls: relayURLs,
            locality: locality,
            followedAuthors: followedAuthors,
            generation: generation
        )
    }
}

private extension RadrootsTodayProjectionUpdate {
    var generatedValue: FfiTodayProjectionUpdate {
        switch self {
        case .incremental: .incremental
        case .rebuild: .rebuild
        }
    }
}

private extension FfiTodayRefreshRecord {
    var appValue: RadrootsTodayRefreshReceipt {
        RadrootsTodayRefreshReceipt(
            update: update.appValue,
            sourceEvents: sourceEvents,
            visibleCards: visibleCards,
            profiles: profiles,
            threadEntries: threadEntries,
            contentGeneration: contentGeneration,
            changed: changed
        )
    }
}

private extension FfiTodayProjectionUpdate {
    var appValue: RadrootsTodayProjectionUpdate {
        switch self {
        case .incremental: .incremental
        case .rebuild: .rebuild
        }
    }
}

private extension FfiTodayPageRecord {
    var appValue: RadrootsTodayPage {
        RadrootsTodayPage(
            asOfUnixSeconds: asOfUnixS,
            items: items.map(\.appValue),
            nextCursor: nextCursor
        )
    }
}

private extension FfiTodayCardRecord {
    var appValue: RadrootsTodayCard {
        RadrootsTodayCard(
            id: cardId,
            type: cardType.appValue,
            sourceEventID: sourceEventId,
            sourceAddress: sourceAddress,
            authorPublicKey: authorPublicKey,
            contractID: contractId,
            title: title,
            content: content,
            authoredAtUnixSeconds: authoredAtUnixS,
            effectiveAtUnixSeconds: effectiveAtUnixS,
            eventStartUnixSeconds: eventStartUnixS,
            eventEndUnixSeconds: eventEndUnixS,
            location: location,
            priceAmount: priceAmount,
            priceCurrency: priceCurrency,
            priceUnit: priceUnit,
            quantity: quantity,
            foodSummary: foodSummary,
            foodPublishedAtUnixSeconds: foodPublishedAtUnixS,
            foodStatus: foodStatus,
            contextRank: contextRank,
            inclusionReason: inclusionReason,
            media: media.map(\.appValue),
            lifecycle: lifecycle.appValue,
            rankDigest: rankDigest,
            authorProfile: authorProfile?.appValue,
            thread: thread.map(\.appValue),
            localOperationID: localOperationId,
            localOperationState: localOperationState
        )
    }
}

private extension FfiTodayCardType {
    var appValue: RadrootsTodayCardType {
        switch self {
        case .update: .update
        case .photoUpdate: .photoUpdate
        case .ask: .ask
        case .event: .event
        case .foodAvailability: .foodAvailability
        }
    }
}

private extension FfiMediaReferenceRecord {
    var appValue: RadrootsMediaReference {
        RadrootsMediaReference(
            url: url,
            sha256: sha256,
            mediaType: mediaType,
            width: width,
            height: height,
            byteSize: byteSize,
            alt: alt,
            verification: verification.appValue
        )
    }
}

private extension FfiMediaVerificationState {
    var appValue: RadrootsMediaVerificationState {
        switch self {
        case .pending: .pending
        case .verified: .verified
        case .failed: .failed
        case .unavailable: .unavailable
        }
    }
}

private extension FfiProfileRecord {
    var appValue: RadrootsProfileSummary {
        RadrootsProfileSummary(
            authorPublicKey: authorPublicKey,
            name: name,
            displayName: displayName,
            about: about,
            picture: picture?.appValue,
            banner: banner?.appValue,
            nip05: nip05,
            website: website,
            lightningAddress: lightningAddress
        )
    }
}

private extension FfiSearchResultRecord {
    var appValue: RadrootsSearchResult {
        RadrootsSearchResult(
            type: resultType.appValue,
            id: stableId,
            card: card?.appValue,
            profile: profile?.appValue
        )
    }
}

private extension FfiSearchResultType {
    var appValue: RadrootsSearchResultType {
        switch self {
        case .card: .card
        case .profile: .profile
        }
    }
}

private extension FfiMeRecord {
    var appValue: RadrootsMeSnapshot {
        RadrootsMeSnapshot(
            publicKey: publicKey,
            profile: profile?.appValue,
            cards: cards.map(\.appValue)
        )
    }
}

private extension FfiThreadEntryRecord {
    var appValue: RadrootsThreadEntry {
        RadrootsThreadEntry(
            id: eventId,
            authorPublicKey: authorPublicKey,
            content: content,
            authoredAtUnixSeconds: authoredAtUnixS,
            type: profile.appValue,
            root: root,
            parentEventID: parentEventId,
            authorProfile: authorProfile?.appValue
        )
    }
}

private extension FfiThreadProfile {
    var appValue: RadrootsThreadEntryType {
        switch self {
        case .profile: .profile
        case .reply: .reply
        case .comment: .comment
        case .deletion: .deletion
        }
    }
}

private extension FfiCardLifecycleState {
    var appValue: RadrootsCardLifecycleState {
        switch self {
        case .active: .active
        case .sold: .sold
        case .past: .past
        }
    }
}

private extension FfiAddSchemaRecord {
    var appValue: RadrootsAddSchema {
        RadrootsAddSchema(
            schemaVersion: schemaVersion,
            commandType: commandType.appValue,
            label: label,
            fields: fields.map(\.appValue)
        )
    }
}

private extension FfiAddFieldRecord {
    var appValue: RadrootsAddField {
        RadrootsAddField(
            schemaVersion: schemaVersion,
            id: id,
            label: label,
            kind: kind.appValue,
            required: required,
            choices: choices,
            maxBytes: maxBytes
        )
    }
}

private extension FfiAddFieldKind {
    var appValue: RadrootsAddFieldKind {
        switch self {
        case .text: .text
        case .multilineText: .multilineText
        case .date: .date
        case .dateTime: .dateTime
        case .decimal: .decimal
        case .choice: .choice
        case .location: .location
        case .media: .media
        }
    }
}

private extension FfiAddCommandType {
    var appValue: RadrootsAddCommandType {
        switch self {
        case .createUpdate: .createUpdate
        case .createPhotoUpdate: .createPhotoUpdate
        case .createAsk: .createAsk
        case .createEvent: .createEvent
        case .createFoodAvailability: .createFoodAvailability
        }
    }
}

private extension RadrootsAddCommandType {
    var generatedValue: FfiAddCommandType {
        switch self {
        case .createUpdate: .createUpdate
        case .createPhotoUpdate: .createPhotoUpdate
        case .createAsk: .createAsk
        case .createEvent: .createEvent
        case .createFoodAvailability: .createFoodAvailability
        }
    }
}

private extension FfiEventTimingKind {
    var appValue: RadrootsEventTiming {
        switch self {
        case .allDay: .allDay
        case .timed: .timed
        }
    }
}

private extension RadrootsEventTiming {
    var generatedValue: FfiEventTimingKind {
        switch self {
        case .allDay: .allDay
        case .timed: .timed
        }
    }
}

private extension RadrootsAddRuntimeInput {
    var generatedValue: FfiAddDraftInput {
        FfiAddDraftInput(
            schemaVersion: 1,
            commandType: form.commandType.generatedValue,
            content: form.content,
            identifier: form.identifier,
            title: form.title,
            summary: form.summary,
            location: form.location,
            eventTiming: form.eventTiming?.generatedValue,
            eventStartDate: form.eventStartDate,
            eventEndDate: form.eventEndDate,
            eventStartUnixS: form.eventStartUnixSeconds,
            eventEndUnixS: form.eventEndUnixSeconds,
            eventTimezone: form.eventTimezone,
            priceAmount: form.priceAmount,
            currency: form.currency,
            unit: form.unit,
            quantity: form.quantity,
            foodPublishedAtUnixS: form.foodPublishedAtUnixSeconds,
            foodStatus: form.foodStatus,
            media: media.map(\.generatedValue)
        )
    }
}

private extension RadrootsPreparedMediaHandle {
    var generatedValue: FfiPreparedMediaInput {
        FfiPreparedMediaInput(
            schemaVersion: 1,
            opaqueReference: media.opaqueReference,
            fileDescriptor: fileDescriptor,
            sha256: media.sha256,
            mediaType: media.mediaType,
            byteSize: media.byteSize,
            width: media.width,
            height: media.height,
            alt: media.alt,
            preparedAtUnixS: media.preparedAtUnixSeconds
        )
    }
}

private extension FfiDraftFormMediaRecord {
    var appValue: RadrootsPreparedMedia {
        RadrootsPreparedMedia(
            opaqueReference: opaqueReference,
            remoteURL: url,
            sha256: sha256,
            mediaType: mediaType,
            byteSize: byteSize,
            width: width,
            height: height,
            alt: alt,
            preparedAtUnixSeconds: preparedAtUnixS
        )
    }
}

private extension FfiDraftFormRecord {
    var appValue: RadrootsAddForm {
        RadrootsAddForm(
            commandType: commandType.appValue,
            content: content,
            identifier: identifier,
            title: title,
            summary: summary,
            location: location,
            eventTiming: eventTiming?.appValue,
            eventStartDate: eventStartDate,
            eventEndDate: eventEndDate,
            eventStartUnixSeconds: eventStartUnixS,
            eventEndUnixSeconds: eventEndUnixS,
            eventTimezone: eventTimezone,
            priceAmount: priceAmount,
            currency: currency,
            unit: unit,
            quantity: quantity,
            foodPublishedAtUnixSeconds: foodPublishedAtUnixS,
            foodStatus: foodStatus,
            media: media.map(\.appValue)
        )
    }
}

private extension FfiDraftStatusRecord {
    var appValue: RadrootsDraftStatus {
        RadrootsDraftStatus(
            id: draftId,
            revision: revision,
            authorPublicKey: authorPublicKey,
            kind: kind.appValue,
            commandType: commandType.appValue,
            form: form?.appValue,
            state: state.appValue,
            cardID: cardId,
            operationID: operationId,
            createdAtUnixMilliseconds: createdAtUnixMs,
            updatedAtUnixMilliseconds: updatedAtUnixMs,
            media: media.map(\.appValue),
            settlement: settlement?.appValue
        )
    }
}

private extension FfiDraftKind {
    var appValue: RadrootsDraftKind {
        switch self {
        case .add: .add
        case .retraction: .retraction
        }
    }
}

private extension FfiOutboxState {
    var appValue: RadrootsOutboxState {
        switch self {
        case .draft: .draft
        case .mediaPreparing: .mediaPreparing
        case .mediaUploading: .mediaUploading
        case .readyToSign: .readyToSign
        case .signing: .signing
        case .signed: .signed
        case .queued: .queued
        case .delivering: .delivering
        case .partiallyDelivered: .partiallyDelivered
        case .retryable: .retryable
        case .terminal: .terminal
        case .cancelled: .cancelled
        case .complete: .complete
        }
    }
}

private extension FfiDraftMediaRecord {
    var appValue: RadrootsDraftMediaStatus {
        RadrootsDraftMediaStatus(
            url: url,
            stage: stage.appValue,
            uploadAttempts: uploadAttempts,
            verifiedAtUnixMilliseconds: verifiedAtUnixMs,
            possibleOrphan: possibleOrphan,
            orphanReasonCode: orphanReasonCode,
            orphanRecordedAtUnixMilliseconds: orphanRecordedAtUnixMs
        )
    }
}

private extension FfiMediaStage {
    var appValue: RadrootsDraftMediaStage {
        switch self {
        case .pending: .pending
        case .preparing: .preparing
        case .uploading: .uploading
        case .verified: .verified
        case .failed: .failed
        case .orphaned: .orphaned
        }
    }
}

private extension FfiOperationSettlementRecord {
    var appValue: RadrootsOperationSettlement {
        RadrootsOperationSettlement(
            artifacts: artifacts,
            signed: signed,
            admitted: admitted,
            pending: pending,
            retryable: retryable,
            indeterminate: indeterminate,
            failedTerminal: failedTerminal,
            cancelled: cancelled,
            deliveryPlans: deliveryPlans,
            deliverySatisfied: deliverySatisfied,
            deliveryPending: deliveryPending,
            deliveryRetryable: deliveryRetryable,
            deliveryExhausted: deliveryExhausted,
            deliveryFailedTerminal: deliveryFailedTerminal,
            deliveryCancelled: deliveryCancelled
        )
    }
}

private extension RadrootsRetractionDraftInput {
    var generatedValue: FfiRetractionDraftInput {
        FfiRetractionDraftInput(
            schemaVersion: 1,
            commandType: commandType.generatedValue,
            targetCardId: targetCardID,
            targetEventId: targetEventID,
            targetKind: targetKind,
            targetAddress: targetAddress,
            reason: reason
        )
    }
}

private extension RadrootsBlossomUploadIntent {
    var generatedValue: FfiBlossomUploadIntent {
        FfiBlossomUploadIntent(
            schemaVersion: 1,
            draftId: draftID,
            expectedRevision: expectedRevision,
            media: media.generatedValue
        )
    }
}
