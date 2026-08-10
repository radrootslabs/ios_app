import Foundation

enum RadrootsTodayLoadState: Sendable, Equatable {
    case idle
    case loading
    case loaded
    case empty
    case offline(message: String)
    case failed(message: String)
}

@MainActor
final class RadrootsTodayStore: ObservableObject {
    @Published private(set) var contexts: [RadrootsLocalNetwork]
    @Published private(set) var selectedContextID: String?
    @Published private(set) var cards: [RadrootsTodayCard] = []
    @Published private(set) var state: RadrootsTodayLoadState = .idle
    @Published private(set) var isLoadingNextPage = false

    private let runtimeClient: RadrootsRuntimeClient
    private let pageSize: UInt16
    private let now: @Sendable () -> UInt64
    private var frozenAsOfUnixSeconds: UInt64?
    private var nextCursor: String?
    private var requestGeneration: UInt64 = 0
    private var observationTask: Task<Void, Never>?
    private var reloadTask: Task<Void, Never>?
    private var isStarted = false

    init(
        runtimeClient: RadrootsRuntimeClient,
        contexts: [RadrootsLocalNetwork] = [],
        selectedContextID: String? = nil,
        pageSize: UInt16 = 20,
        now: @escaping @Sendable () -> UInt64 = {
            UInt64(Date().timeIntervalSince1970)
        }
    ) {
        self.runtimeClient = runtimeClient
        self.contexts = Self.unique(contexts)
        self.pageSize = min(max(pageSize, 1), 100)
        self.now = now
        if let selectedContextID,
           self.contexts.contains(where: { $0.id == selectedContextID })
        {
            self.selectedContextID = selectedContextID
        } else {
            self.selectedContextID = self.contexts.first?.id
        }
    }

    deinit {
        observationTask?.cancel()
        reloadTask?.cancel()
    }

    var selectedContext: RadrootsLocalNetwork? {
        contexts.first(where: { $0.id == selectedContextID })
    }

    var canLoadNextPage: Bool {
        nextCursor != nil && !isLoadingNextPage
    }

    func configure(snapshot: RadrootsRuntimeSnapshot) {
        guard contexts.isEmpty else { return }
        let context = RadrootsLocalNetwork.defaultContext(snapshot: snapshot)
        contexts = [context]
        selectedContextID = context.id
    }

    func start() async {
        guard !isStarted else { return }
        isStarted = true
        observationTask = Task { [weak self, runtimeClient] in
            do {
                let changes = try await runtimeClient.changes(bufferCapacity: 16)
                for await change in changes {
                    guard !Task.isCancelled else { break }
                    switch change.kind {
                    case .today, .drafts, .media, .identity, .profile:
                        await self?.reload(refreshProjection: false)
                    case .initial, .settings, .relay, .lifecycle:
                        continue
                    }
                }
            } catch {
                // Loading remains available from the durable local projection.
            }
            self?.observationDidFinish()
        }
        await reload()
    }

    func stop() {
        isStarted = false
        requestGeneration &+= 1
        observationTask?.cancel()
        observationTask = nil
        reloadTask?.cancel()
        reloadTask = nil
        isLoadingNextPage = false
    }

    func selectContext(id: String) {
        guard id != selectedContextID,
              contexts.contains(where: { $0.id == id })
        else {
            return
        }
        selectedContextID = id
        requestGeneration &+= 1
        reloadTask?.cancel()
        reloadTask = Task { [weak self] in
            await self?.reload()
        }
    }

    func replaceContexts(_ updatedContexts: [RadrootsLocalNetwork], selectedID: String?) {
        let updatedContexts = Self.unique(updatedContexts)
        guard !updatedContexts.isEmpty else { return }
        contexts = updatedContexts
        selectedContextID = selectedID.flatMap { requested in
            updatedContexts.contains(where: { $0.id == requested }) ? requested : nil
        } ?? updatedContexts.first?.id
        requestGeneration &+= 1
        reloadTask?.cancel()
        reloadTask = Task { [weak self] in
            await self?.reload()
        }
    }

    func reload(
        refreshProjection: Bool = true,
        update: RadrootsTodayProjectionUpdate = .incremental
    ) async {
        guard let context = selectedContext else {
            cards = []
            state = .failed(message: "Choose a local network to load Today.")
            return
        }

        requestGeneration &+= 1
        let generation = requestGeneration
        frozenAsOfUnixSeconds = nil
        nextCursor = nil
        isLoadingNextPage = false
        if cards.isEmpty {
            state = .loading
        }

        var refreshFailure: Error?
        if refreshProjection {
            do {
                _ = try await runtimeClient.refreshToday(
                    context: context,
                    nowUnixSeconds: now(),
                    update: update
                )
            } catch {
                refreshFailure = error
            }
        }

        do {
            let asOf = now()
            let page = try await runtimeClient.todayPage(
                request: .first(
                    context: context,
                    limit: pageSize,
                    asOfUnixSeconds: asOf
                )
            )
            guard generation == requestGeneration, !Task.isCancelled else { return }
            frozenAsOfUnixSeconds = page.asOfUnixSeconds
            nextCursor = page.nextCursor
            cards = Self.unique(page.items)
            state = refreshFailure.map(Self.failureState) ?? (cards.isEmpty ? .empty : .loaded)
        } catch {
            guard generation == requestGeneration, !Task.isCancelled else { return }
            state = Self.failureState(error)
        }
    }

    func loadNextPage() async {
        guard let context = selectedContext,
              let cursor = nextCursor,
              !isLoadingNextPage
        else {
            return
        }
        let generation = requestGeneration
        isLoadingNextPage = true
        defer {
            if generation == requestGeneration {
                isLoadingNextPage = false
            }
        }

        do {
            let page = try await runtimeClient.todayPage(
                request: .after(context: context, limit: pageSize, cursor: cursor)
            )
            guard generation == requestGeneration, !Task.isCancelled else { return }
            guard frozenAsOfUnixSeconds == nil || frozenAsOfUnixSeconds == page.asOfUnixSeconds else {
                state = .failed(message: "Today changed while loading. Refresh to continue.")
                return
            }
            frozenAsOfUnixSeconds = page.asOfUnixSeconds
            nextCursor = page.nextCursor
            cards = Self.unique(cards + page.items)
            switch state {
            case .offline, .failed:
                break
            default:
                state = cards.isEmpty ? .empty : .loaded
            }
        } catch {
            guard generation == requestGeneration, !Task.isCancelled else { return }
            state = Self.failureState(error)
        }
    }

    private static func unique(_ contexts: [RadrootsLocalNetwork]) -> [RadrootsLocalNetwork] {
        var identifiers = Set<String>()
        return contexts.filter { identifiers.insert($0.id).inserted }
    }

    private func observationDidFinish() {
        observationTask = nil
        isStarted = false
    }

    private static func unique(_ cards: [RadrootsTodayCard]) -> [RadrootsTodayCard] {
        var identifiers = Set<String>()
        return cards.filter { identifiers.insert($0.id).inserted }
    }

    private static func failureState(_ error: Error) -> RadrootsTodayLoadState {
        let failure: RadrootsRuntimeFailure? = if case let RadrootsRuntimeClientError.today(value) = error {
            value
        } else if case let RadrootsRuntimeClientError.status(value) = error {
            value
        } else {
            error as? RadrootsRuntimeFailure
        }
        let message = failure?.safeMessage ?? "Today could not be loaded."
        guard let failure else { return .failed(message: message) }
        let category = failure.category.lowercased()
        if failure.retryable || category.contains("network") || category.contains("relay") {
            return .offline(message: message)
        }
        return .failed(message: message)
    }
}
