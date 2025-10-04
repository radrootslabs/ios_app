import Foundation
import Combine

@MainActor
public final class AppState: ObservableObject {
    public enum BootstrapPhase {
        case idle
        case starting
        case ready
    }

    @Published public private(set) var bootstrapPhase: BootstrapPhase = .idle
    @Published public private(set) var infoJSONString: String = ""
    @Published public private(set) var hasKey: Bool = false
    @Published public private(set) var npub: String?
    @Published public private(set) var relayConnectedCount: UInt32 = 0
    @Published public private(set) var relayConnectingCount: UInt32 = 0
    @Published public private(set) var relayLight: RelayLight = .red
    @Published public private(set) var relayLastError: String?

    public var canShowAppContent: Bool { bootstrapPhase == .ready && hasKey }
    public var requiresKeySetup: Bool { bootstrapPhase == .ready && !hasKey }

    public enum RelayLight {
        case red, yellow, green
    }

    public let radroots: Radroots
    public let keys: RadrootsKeys

    private var statusTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()

    public init(radroots: Radroots = Radroots(), keys: RadrootsKeys = RadrootsKeys()) {
        self.radroots = radroots
        self.keys = keys

        keys.$hasKey
            .sink { [weak self] in self?.hasKey = $0 }
            .store(in: &cancellables)

        keys.$npub
            .sink { [weak self] in self?.npub = $0 }
            .store(in: &cancellables)
    }

    deinit {
        statusTask?.cancel()
    }

    public func start() async throws {
        guard bootstrapPhase == .idle else { return }
        bootstrapPhase = .starting
        do {
            try radroots.start()
            if let rt = radroots.runtime {
                keys.loadFromKeychainIfPresent(runtime: rt)
                connectIfPossible()
                if rt.keysIsLoaded() {
                    startPollingStatus()
                }
            }
            refresh()
            bootstrapPhase = .ready
        } catch {
            bootstrapPhase = .idle
            throw error
        }
    }

    public func refresh() {
        guard let rt = radroots.runtime else { return }
        infoJSONString = rt.infoJson()
        hasKey = rt.keysIsLoaded()
        npub = rt.keysNpub()
        updateStatus()
    }

    public func activateAfterKeyGeneration() {
        connectIfPossible()
        startPollingStatus()
        refresh()
    }

    private func connectIfPossible() {
        guard let rt = radroots.runtime, rt.keysIsLoaded() else { return }
        do {
            let relays = try RelaySettings.relays()
            try rt.nostrSetDefaultRelays(relays: relays)
            try rt.nostrConnectIfKeyPresent()
            relayLastError = nil
        } catch {
            relayLastError = error.localizedDescription
        }
    }

    private func startPollingStatus() {
        statusTask?.cancel()
        statusTask = Task { [weak self] in
            while !Task.isCancelled {
                await MainActor.run { self?.updateStatus() }
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
    }

    private func updateStatus() {
        guard let rt = radroots.runtime else { return }
        let s = rt.nostrConnectionStatus()
        relayConnectedCount = s.connected
        relayConnectingCount = s.connecting
        relayLastError = s.lastError

        switch s.light {
        case .green: relayLight = .green
        case .yellow: relayLight = .yellow
        case .red: relayLight = .red
        @unknown default: relayLight = .red
        }
    }
}
