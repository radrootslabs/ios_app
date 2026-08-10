import Foundation

protocol RadrootsRuntimeSubscriptionToken: Sendable {
    func cancel() async
}

protocol RadrootsRuntimeBackend: Sendable {
    func snapshot() async throws -> RadrootsRuntimeSnapshot
    func todayPage(request: RadrootsTodayPageRequest) async throws -> RadrootsTodayPage
    func refreshToday(
        context: RadrootsLocalNetwork,
        nowUnixSeconds: UInt64,
        update: RadrootsTodayProjectionUpdate
    ) async throws -> RadrootsTodayRefreshReceipt
    func search(
        context: RadrootsLocalNetwork,
        query: String,
        limit: UInt16,
        asOfUnixSeconds: UInt64
    ) async throws -> [RadrootsSearchResult]
    func me(
        context: RadrootsLocalNetwork,
        asOfUnixSeconds: UInt64
    ) async throws -> RadrootsMeSnapshot
    func addSchemas() async throws -> [RadrootsAddSchema]
    func saveAddIntent(
        input: RadrootsAddRuntimeInput,
        existingDraftID: String?,
        expectedRevision: UInt64?
    ) async throws -> RadrootsDraftStatus
    func saveRetractionDraft(
        id: String,
        input: RadrootsRetractionDraftInput,
        authoredAtUnixSeconds: UInt64,
        persistedAtUnixMilliseconds: UInt64
    ) async throws -> RadrootsDraftStatus
    func draftStatus(id: String) async throws -> RadrootsDraftStatus
    func draftHeads(limit: UInt16) async throws -> [RadrootsDraftStatus]
    func queueAddIntent(
        id: String,
        expectedRevision: UInt64
    ) async throws -> RadrootsDraftStatus
    func recoverAddIntent(id: String) async throws -> RadrootsDraftStatus
    func uploadAddMediaIntent(input: RadrootsBlossomUploadIntent) async throws -> RadrootsDraftStatus
    func probeBlossom() async throws -> RadrootsBlossomEvidence
    func advanceDraft(id: String, expectedRevision: UInt64) async throws -> RadrootsDraftStatus
    func cancelAddIntent(
        id: String,
        expectedRevision: UInt64
    ) async throws -> RadrootsDraftStatus
    func subscribe(
        bufferCapacity: Int,
        receive: @escaping @Sendable (RadrootsRuntimeChange) async -> Void
    ) async throws -> any RadrootsRuntimeSubscriptionToken
    func shutdown() async throws -> RadrootsRuntimeShutdownReceipt
}

extension RadrootsRuntimeBackend {
    private func supportUnsupported() -> RadrootsRuntimeFailure {
        .local(
            operation: "runtime.support",
            code: "ios.support.unsupported",
            safeMessage: "This supporting surface is unavailable in the current runtime."
        )
    }

    private func addUnsupported() -> RadrootsRuntimeFailure {
        .local(
            operation: "runtime.add",
            code: "ios.add.unsupported",
            safeMessage: "Add is unavailable in this runtime."
        )
    }

    func addSchemas() async throws -> [RadrootsAddSchema] {
        throw addUnsupported()
    }

    func saveAddIntent(
        input _: RadrootsAddRuntimeInput,
        existingDraftID _: String?,
        expectedRevision _: UInt64?
    ) async throws -> RadrootsDraftStatus {
        throw addUnsupported()
    }

    func saveRetractionDraft(
        id _: String,
        input _: RadrootsRetractionDraftInput,
        authoredAtUnixSeconds _: UInt64,
        persistedAtUnixMilliseconds _: UInt64
    ) async throws -> RadrootsDraftStatus {
        throw addUnsupported()
    }

    func draftStatus(id _: String) async throws -> RadrootsDraftStatus {
        throw addUnsupported()
    }

    func draftHeads(limit _: UInt16) async throws -> [RadrootsDraftStatus] {
        throw addUnsupported()
    }

    func queueAddIntent(
        id _: String,
        expectedRevision _: UInt64
    ) async throws -> RadrootsDraftStatus {
        throw addUnsupported()
    }

    func recoverAddIntent(id _: String) async throws -> RadrootsDraftStatus {
        throw addUnsupported()
    }

    func uploadAddMediaIntent(input _: RadrootsBlossomUploadIntent) async throws -> RadrootsDraftStatus {
        throw addUnsupported()
    }

    func probeBlossom() async throws -> RadrootsBlossomEvidence {
        throw supportUnsupported()
    }

    func advanceDraft(id _: String, expectedRevision _: UInt64) async throws -> RadrootsDraftStatus {
        throw addUnsupported()
    }

    func cancelAddIntent(
        id _: String,
        expectedRevision _: UInt64
    ) async throws -> RadrootsDraftStatus {
        throw addUnsupported()
    }

    func search(
        context _: RadrootsLocalNetwork,
        query _: String,
        limit _: UInt16,
        asOfUnixSeconds _: UInt64
    ) async throws -> [RadrootsSearchResult] {
        throw supportUnsupported()
    }

    func me(
        context _: RadrootsLocalNetwork,
        asOfUnixSeconds _: UInt64
    ) async throws -> RadrootsMeSnapshot {
        throw supportUnsupported()
    }
}

struct RadrootsRuntimeBackendStart: Sendable {
    let backend: any RadrootsRuntimeBackend
    let snapshot: RadrootsRuntimeSnapshot
}

typealias RadrootsRuntimeBackendFactory = @Sendable (
    RadrootsRuntimeLaunchConfiguration
) async throws -> RadrootsRuntimeBackendStart

actor RadrootsRuntimeClient {
    private struct StartupOperation: Sendable {
        let generation: UInt64
        let configuration: RadrootsRuntimeLaunchConfiguration
        let task: Task<Result<RadrootsRuntimeBackendStart, RadrootsRuntimeFailure>, Never>
    }

    private struct ShutdownOperation: Sendable {
        let generation: UInt64
        let task: Task<Result<RadrootsRuntimeShutdownReceipt, RadrootsRuntimeFailure>, Never>
    }

    private struct Subscription {
        let generation: UInt64
        let continuation: AsyncStream<RadrootsRuntimeChange>.Continuation
        var token: (any RadrootsRuntimeSubscriptionToken)?
    }

    private let factory: RadrootsRuntimeBackendFactory
    private var generation: UInt64 = 0
    private var lifecycleState: RadrootsRuntimeLifecycle = .stopped
    private var configuration: RadrootsRuntimeLaunchConfiguration?
    private var backend: (any RadrootsRuntimeBackend)?
    private var startupOperation: StartupOperation?
    private var shutdownOperation: ShutdownOperation?
    private var subscriptions: [UUID: Subscription] = [:]

    init(factory: @escaping RadrootsRuntimeBackendFactory) {
        self.factory = factory
    }

    func lifecycle() -> RadrootsRuntimeLifecycle {
        lifecycleState
    }

    func start(
        configuration requestedConfiguration: RadrootsRuntimeLaunchConfiguration
    ) async throws -> RadrootsRuntimeSnapshot {
        if let shutdownOperation {
            _ = try await finishShutdown(shutdownOperation)
        }

        if let backend,
           configuration == requestedConfiguration,
           case .running = lifecycleState
        {
            return try await backendSnapshot(backend)
        }

        if let startupOperation,
           startupOperation.configuration == requestedConfiguration
        {
            return try await finishStartup(startupOperation)
        }

        if startupOperation != nil || backend != nil {
            let operation = beginShutdown()
            _ = try await finishShutdown(operation)
        }

        generation &+= 1
        let operationGeneration = generation
        lifecycleState = .starting(generation: operationGeneration)

        let factory = factory
        let task = Task<Result<RadrootsRuntimeBackendStart, RadrootsRuntimeFailure>, Never> {
            do {
                return try await .success(factory(requestedConfiguration))
            } catch {
                return .failure(Self.failure(from: error, operation: "runtime.start"))
            }
        }
        let operation = StartupOperation(
            generation: operationGeneration,
            configuration: requestedConfiguration,
            task: task
        )
        startupOperation = operation
        return try await finishStartup(operation)
    }

    func retry(
        configuration requestedConfiguration: RadrootsRuntimeLaunchConfiguration
    ) async throws -> RadrootsRuntimeSnapshot {
        _ = try await stop()
        return try await start(configuration: requestedConfiguration)
    }

    func snapshot() async throws -> RadrootsRuntimeSnapshot {
        guard let backend, case .running = lifecycleState else {
            throw RadrootsRuntimeClientError.notRunning
        }
        return try await backendSnapshot(backend)
    }

    func todayPage(request: RadrootsTodayPageRequest) async throws -> RadrootsTodayPage {
        guard let backend, case .running = lifecycleState else {
            throw RadrootsRuntimeClientError.notRunning
        }
        do {
            return try await backend.todayPage(request: request)
        } catch {
            throw RadrootsRuntimeClientError.today(
                Self.failure(from: error, operation: "runtime.today.page")
            )
        }
    }

    func refreshToday(
        context: RadrootsLocalNetwork,
        nowUnixSeconds: UInt64,
        update: RadrootsTodayProjectionUpdate = .incremental
    ) async throws -> RadrootsTodayRefreshReceipt {
        guard let backend, case .running = lifecycleState else {
            throw RadrootsRuntimeClientError.notRunning
        }
        do {
            return try await backend.refreshToday(
                context: context,
                nowUnixSeconds: nowUnixSeconds,
                update: update
            )
        } catch {
            throw RadrootsRuntimeClientError.today(
                Self.failure(from: error, operation: "runtime.today.refresh")
            )
        }
    }

    func search(
        context: RadrootsLocalNetwork,
        query: String,
        limit: UInt16 = 50,
        asOfUnixSeconds: UInt64
    ) async throws -> [RadrootsSearchResult] {
        try await supportOperation("runtime.support.search") { backend in
            try await backend.search(
                context: context,
                query: query,
                limit: limit,
                asOfUnixSeconds: asOfUnixSeconds
            )
        }
    }

    func me(
        context: RadrootsLocalNetwork,
        asOfUnixSeconds: UInt64
    ) async throws -> RadrootsMeSnapshot {
        try await supportOperation("runtime.support.me") { backend in
            try await backend.me(context: context, asOfUnixSeconds: asOfUnixSeconds)
        }
    }

    func addSchemas() async throws -> [RadrootsAddSchema] {
        try await addOperation("runtime.add.schemas") { backend in
            try await backend.addSchemas()
        }
    }

    func saveAddIntent(
        input: RadrootsAddRuntimeInput,
        existingDraftID: String?,
        expectedRevision: UInt64?
    ) async throws -> RadrootsDraftStatus {
        try await addOperation("runtime.add.save") { backend in
            try await backend.saveAddIntent(
                input: input,
                existingDraftID: existingDraftID,
                expectedRevision: expectedRevision
            )
        }
    }

    func saveRetractionDraft(
        id: String,
        input: RadrootsRetractionDraftInput,
        authoredAtUnixSeconds: UInt64,
        persistedAtUnixMilliseconds: UInt64
    ) async throws -> RadrootsDraftStatus {
        try await addOperation("runtime.add.retract") { backend in
            try await backend.saveRetractionDraft(
                id: id,
                input: input,
                authoredAtUnixSeconds: authoredAtUnixSeconds,
                persistedAtUnixMilliseconds: persistedAtUnixMilliseconds
            )
        }
    }

    func draftStatus(id: String) async throws -> RadrootsDraftStatus {
        try await addOperation("runtime.add.status") { backend in
            try await backend.draftStatus(id: id)
        }
    }

    func draftHeads(limit: UInt16 = 100) async throws -> [RadrootsDraftStatus] {
        try await addOperation("runtime.add.heads") { backend in
            try await backend.draftHeads(limit: limit)
        }
    }

    func queueAddIntent(
        id: String,
        expectedRevision: UInt64
    ) async throws -> RadrootsDraftStatus {
        try await addOperation("runtime.add.queue") { backend in
            try await backend.queueAddIntent(
                id: id,
                expectedRevision: expectedRevision
            )
        }
    }

    func recoverAddIntent(id: String) async throws -> RadrootsDraftStatus {
        try await addOperation("runtime.add.recover") { backend in
            try await backend.recoverAddIntent(id: id)
        }
    }

    func uploadAddMediaIntent(input: RadrootsBlossomUploadIntent) async throws -> RadrootsDraftStatus {
        try await addOperation("runtime.add.media") { backend in
            try await backend.uploadAddMediaIntent(input: input)
        }
    }

    func probeBlossom() async throws -> RadrootsBlossomEvidence {
        try await supportOperation("runtime.blossom.probe") { backend in
            try await backend.probeBlossom()
        }
    }

    func advanceDraft(id: String, expectedRevision: UInt64) async throws -> RadrootsDraftStatus {
        try await addOperation("runtime.add.advance") { backend in
            try await backend.advanceDraft(id: id, expectedRevision: expectedRevision)
        }
    }

    func cancelAddIntent(
        id: String,
        expectedRevision: UInt64
    ) async throws -> RadrootsDraftStatus {
        try await addOperation("runtime.add.cancel") { backend in
            try await backend.cancelAddIntent(
                id: id,
                expectedRevision: expectedRevision
            )
        }
    }

    func changes(bufferCapacity: Int = 16) async throws -> AsyncStream<RadrootsRuntimeChange> {
        guard (1 ... 64).contains(bufferCapacity) else {
            throw RadrootsRuntimeClientError.invalidBufferCapacity
        }
        guard let backend, case .running = lifecycleState else {
            throw RadrootsRuntimeClientError.notRunning
        }

        let id = UUID()
        let subscriptionGeneration = generation
        let pair = AsyncStream.makeStream(
            of: RadrootsRuntimeChange.self,
            bufferingPolicy: .bufferingNewest(bufferCapacity)
        )
        pair.continuation.onTermination = { [weak self] _ in
            Task {
                await self?.cancelSubscription(id: id, generation: subscriptionGeneration)
            }
        }
        subscriptions[id] = Subscription(
            generation: subscriptionGeneration,
            continuation: pair.continuation,
            token: nil
        )

        do {
            let token = try await backend.subscribe(bufferCapacity: bufferCapacity) { [weak self] change in
                await self?.receive(
                    change,
                    subscriptionID: id,
                    generation: subscriptionGeneration
                )
            }
            guard generation == subscriptionGeneration,
                  var subscription = subscriptions[id]
            else {
                await token.cancel()
                pair.continuation.finish()
                throw RadrootsRuntimeClientError.superseded
            }
            subscription.token = token
            subscriptions[id] = subscription
            return pair.stream
        } catch let error as RadrootsRuntimeClientError {
            subscriptions.removeValue(forKey: id)?.continuation.finish()
            throw error
        } catch {
            subscriptions.removeValue(forKey: id)?.continuation.finish()
            throw RadrootsRuntimeClientError.subscription(
                Self.failure(from: error, operation: "runtime.subscribe")
            )
        }
    }

    func stop() async throws -> RadrootsRuntimeShutdownReceipt {
        if let shutdownOperation {
            return try await finishShutdown(shutdownOperation)
        }
        guard startupOperation != nil || backend != nil || !subscriptions.isEmpty else {
            lifecycleState = .stopped
            return .alreadyStopped
        }
        return try await finishShutdown(beginShutdown())
    }

    private func finishStartup(
        _ operation: StartupOperation
    ) async throws -> RadrootsRuntimeSnapshot {
        let result = await operation.task.value
        guard generation == operation.generation else {
            throw RadrootsRuntimeClientError.superseded
        }

        if let active = startupOperation,
           active.generation == operation.generation
        {
            startupOperation = nil
        } else if let backend,
                  configuration == operation.configuration,
                  case .running = lifecycleState
        {
            return try await backendSnapshot(backend)
        } else {
            throw RadrootsRuntimeClientError.superseded
        }

        switch result {
        case let .success(started):
            backend = started.backend
            configuration = operation.configuration
            lifecycleState = .running(generation: operation.generation)
            return started.snapshot
        case let .failure(failure):
            lifecycleState = .failed(generation: operation.generation, failure: failure)
            throw RadrootsRuntimeClientError.startup(failure)
        }
    }

    private func beginShutdown() -> ShutdownOperation {
        generation &+= 1
        let operationGeneration = generation
        let pendingStartup = startupOperation
        let activeBackend = backend
        let activeSubscriptions = Array(subscriptions.values)

        startupOperation = nil
        backend = nil
        configuration = nil
        subscriptions.removeAll()
        lifecycleState = .stopping(generation: operationGeneration)

        let task = Task<Result<RadrootsRuntimeShutdownReceipt, RadrootsRuntimeFailure>, Never> {
            for subscription in activeSubscriptions {
                subscription.continuation.finish()
                await subscription.token?.cancel()
            }

            let backendToClose: (any RadrootsRuntimeBackend)?
            if let activeBackend {
                backendToClose = activeBackend
            } else if let pendingStartup {
                switch await pendingStartup.task.value {
                case let .success(started):
                    backendToClose = started.backend
                case let .failure(failure):
                    return .failure(failure)
                }
            } else {
                backendToClose = nil
            }

            guard let backendToClose else {
                return .success(.alreadyStopped)
            }
            do {
                return try await .success(backendToClose.shutdown())
            } catch {
                return .failure(Self.failure(from: error, operation: "runtime.shutdown"))
            }
        }
        let operation = ShutdownOperation(generation: operationGeneration, task: task)
        shutdownOperation = operation
        return operation
    }

    private func finishShutdown(
        _ operation: ShutdownOperation
    ) async throws -> RadrootsRuntimeShutdownReceipt {
        let result = await operation.task.value
        if shutdownOperation?.generation == operation.generation {
            shutdownOperation = nil
            switch result {
            case .success:
                lifecycleState = .stopped
            case let .failure(failure):
                lifecycleState = .failed(generation: operation.generation, failure: failure)
            }
        }

        switch result {
        case let .success(receipt):
            return receipt
        case let .failure(failure):
            throw RadrootsRuntimeClientError.shutdown(failure)
        }
    }

    private func backendSnapshot(
        _ backend: any RadrootsRuntimeBackend
    ) async throws -> RadrootsRuntimeSnapshot {
        do {
            return try await backend.snapshot()
        } catch {
            throw RadrootsRuntimeClientError.status(
                Self.failure(from: error, operation: "runtime.status")
            )
        }
    }

    private func addOperation<T: Sendable>(
        _ operation: String,
        _ body: @Sendable (any RadrootsRuntimeBackend) async throws -> T
    ) async throws -> T {
        guard let backend, case .running = lifecycleState else {
            throw RadrootsRuntimeClientError.notRunning
        }
        do {
            return try await body(backend)
        } catch {
            throw RadrootsRuntimeClientError.add(
                Self.failure(from: error, operation: operation)
            )
        }
    }

    private func supportOperation<T: Sendable>(
        _ operation: String,
        _ body: @Sendable (any RadrootsRuntimeBackend) async throws -> T
    ) async throws -> T {
        guard let backend, case .running = lifecycleState else {
            throw RadrootsRuntimeClientError.notRunning
        }
        do {
            return try await body(backend)
        } catch {
            throw RadrootsRuntimeClientError.support(
                Self.failure(from: error, operation: operation)
            )
        }
    }

    private func receive(
        _ change: RadrootsRuntimeChange,
        subscriptionID: UUID,
        generation subscriptionGeneration: UInt64
    ) {
        guard generation == subscriptionGeneration,
              let subscription = subscriptions[subscriptionID],
              subscription.generation == subscriptionGeneration
        else {
            return
        }
        subscription.continuation.yield(change)
    }

    private func cancelSubscription(id: UUID, generation subscriptionGeneration: UInt64) async {
        guard let subscription = subscriptions[id],
              subscription.generation == subscriptionGeneration
        else {
            return
        }
        subscriptions.removeValue(forKey: id)
        subscription.continuation.finish()
        await subscription.token?.cancel()
    }

    private static func failure(from error: Error, operation: String) -> RadrootsRuntimeFailure {
        if let failure = error as? RadrootsRuntimeFailure {
            return failure
        }
        if case let RadrootsRuntimeClientError.startup(failure) = error {
            return failure
        }
        if case let RadrootsRuntimeClientError.subscription(failure) = error {
            return failure
        }
        if case let RadrootsRuntimeClientError.status(failure) = error {
            return failure
        }
        if case let RadrootsRuntimeClientError.today(failure) = error {
            return failure
        }
        if case let RadrootsRuntimeClientError.add(failure) = error {
            return failure
        }
        if case let RadrootsRuntimeClientError.support(failure) = error {
            return failure
        }
        if case let RadrootsRuntimeClientError.shutdown(failure) = error {
            return failure
        }
        return .local(
            operation: operation,
            code: "ios.runtime.unexpected",
            safeMessage: "The Radroots runtime could not complete the operation."
        )
    }
}
