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
    func subscribe(
        bufferCapacity: Int,
        receive: @escaping @Sendable (RadrootsRuntimeChange) async -> Void
    ) async throws -> any RadrootsRuntimeSubscriptionToken
    func shutdown() async throws -> RadrootsRuntimeShutdownReceipt
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
