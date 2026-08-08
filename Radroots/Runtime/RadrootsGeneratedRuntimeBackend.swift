import Foundation
import RadrootsKitBindings

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
                crateName: info.sdk.crateName,
                crateVersion: info.sdk.crateVersion,
                isClosed: info.sdkClosed
            )
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
            let runtime = try await RadrootsRuntime(
                applicationSupportDirectory: configuration.applicationSupportDirectory,
                publicKeyHex: configuration.publicKeyHex,
                sourceGenerationHex: configuration.sourceGenerationHex,
                sourceGenerationCreatedAtUnixMs: configuration.sourceGenerationCreatedAtUnixMilliseconds,
                protectedData: configuration.protectedData.generatedValue
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
                try runtime.configurePublicBlossom(origins: configuration.blossomOrigins)
            case .simulator:
                try runtime.configureSimulatorRelays(loopbackRelays: configuration.writableRelays)
                try runtime.configureSimulatorBlossom(origins: configuration.blossomOrigins)
            case .device:
                try runtime.configureDeviceRelays(writableRelays: configuration.writableRelays)
                try runtime.configureDeviceBlossom(origins: configuration.blossomOrigins)
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

private extension FfiRuntimeChangeKind {
    var appValue: RadrootsRuntimeChangeKind {
        switch self {
        case .initial: .initial
        case .identity: .identity
        case .today: .today
        case .drafts: .drafts
        case .relay: .relay
        case .media: .media
        case .lifecycle: .lifecycle
        }
    }
}
