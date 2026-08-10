import Foundation

enum RadrootsSupportingLoadState: Sendable, Equatable {
    case idle
    case loading
    case loaded
    case empty
    case failed(String)
}

@MainActor
final class RadrootsSearchStore: ObservableObject {
    @Published private(set) var query = ""
    @Published private(set) var results: [RadrootsSearchResult] = []
    @Published private(set) var state: RadrootsSupportingLoadState = .idle

    private let runtimeClient: RadrootsRuntimeClient
    private let now: @Sendable () -> UInt64
    private var context: RadrootsLocalNetwork?
    private var generation: UInt64 = 0

    init(
        runtimeClient: RadrootsRuntimeClient,
        now: @escaping @Sendable () -> UInt64 = { UInt64(Date().timeIntervalSince1970) }
    ) {
        self.runtimeClient = runtimeClient
        self.now = now
    }

    func configure(context: RadrootsLocalNetwork?) {
        guard self.context != context else { return }
        generation &+= 1
        self.context = context
        results = []
        state = .idle
    }

    func updateQuery(_ value: String) {
        query = String(value.prefix(256))
        if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            generation &+= 1
            results = []
            state = .idle
        }
    }

    func search() async {
        guard let context else {
            state = .failed("Choose a local network before searching.")
            return
        }
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty,
              normalized.utf8.count <= 256,
              !normalized.contains(where: \.isNewline),
              !normalized.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
        else {
            results = []
            state = .idle
            return
        }

        generation &+= 1
        let requestedGeneration = generation
        state = .loading
        do {
            let loaded = try await runtimeClient.search(
                context: context,
                query: normalized,
                limit: 50,
                asOfUnixSeconds: now()
            )
            guard requestedGeneration == generation, !Task.isCancelled else { return }
            results = Self.unique(loaded)
            state = results.isEmpty ? .empty : .loaded
        } catch {
            guard requestedGeneration == generation, !Task.isCancelled else { return }
            results = []
            state = .failed(Self.message(for: error))
        }
    }

    func stop() {
        generation &+= 1
        state = .idle
    }

    private static func unique(_ values: [RadrootsSearchResult]) -> [RadrootsSearchResult] {
        var identifiers = Set<String>()
        return values.filter { identifiers.insert("\($0.type):\($0.id)").inserted }
    }

    private static func message(for error: Error) -> String {
        if case let RadrootsRuntimeClientError.support(failure) = error {
            return failure.safeMessage
        }
        return (error as? LocalizedError)?.errorDescription ?? "Search is unavailable."
    }
}

@MainActor
final class RadrootsMeStore: ObservableObject {
    @Published private(set) var snapshot: RadrootsMeSnapshot?
    @Published private(set) var state: RadrootsSupportingLoadState = .idle

    private let runtimeClient: RadrootsRuntimeClient
    private let now: @Sendable () -> UInt64
    private var context: RadrootsLocalNetwork?
    private var generation: UInt64 = 0
    private var observationTask: Task<Void, Never>?
    private var isStarted = false

    init(
        runtimeClient: RadrootsRuntimeClient,
        now: @escaping @Sendable () -> UInt64 = { UInt64(Date().timeIntervalSince1970) }
    ) {
        self.runtimeClient = runtimeClient
        self.now = now
    }

    deinit {
        observationTask?.cancel()
    }

    func configure(context: RadrootsLocalNetwork?) {
        guard self.context != context else { return }
        generation &+= 1
        self.context = context
        snapshot = nil
        state = .idle
    }

    func start() async {
        if !isStarted {
            isStarted = true
            observationTask = Task { [weak self, runtimeClient] in
                do {
                    let changes = try await runtimeClient.changes(bufferCapacity: 8)
                    for await change in changes {
                        guard !Task.isCancelled else { break }
                        switch change.kind {
                        case .today, .identity, .profile, .media, .drafts:
                            await self?.reload()
                        case .initial, .settings, .relay, .lifecycle:
                            continue
                        }
                    }
                } catch {
                    // Manual loading remains available from the durable projection.
                }
                self?.observationDidFinish()
            }
        }
        await reload()
    }

    func reload() async {
        guard let context else {
            snapshot = nil
            state = .failed("Choose a local network before loading your profile.")
            return
        }
        generation &+= 1
        let requestedGeneration = generation
        if snapshot == nil {
            state = .loading
        }
        do {
            let loaded = try await runtimeClient.me(
                context: context,
                asOfUnixSeconds: now()
            )
            guard requestedGeneration == generation, !Task.isCancelled else { return }
            snapshot = loaded
            state = loaded.cards.isEmpty && loaded.profile == nil ? .empty : .loaded
        } catch {
            guard requestedGeneration == generation, !Task.isCancelled else { return }
            state = .failed(Self.message(for: error))
        }
    }

    func stop() {
        generation &+= 1
        isStarted = false
        observationTask?.cancel()
        observationTask = nil
    }

    private func observationDidFinish() {
        observationTask = nil
        isStarted = false
    }

    private static func message(for error: Error) -> String {
        if case let RadrootsRuntimeClientError.support(failure) = error {
            return failure.safeMessage
        }
        return (error as? LocalizedError)?.errorDescription ?? "Your profile is unavailable."
    }
}
