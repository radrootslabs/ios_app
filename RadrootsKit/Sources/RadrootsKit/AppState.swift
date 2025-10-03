import Foundation
import Combine

@MainActor
public final class AppState: ObservableObject {
    @Published public private(set) var infoJSONString: String = ""
    @Published public private(set) var hasKey: Bool = false
    @Published public private(set) var npub: String?
    @Published public private(set) var relayConnectedCount: UInt32 = 0
    @Published public private(set) var relayConnectingCount: UInt32 = 0
    @Published public private(set) var relayLight: RelayLight = .red
    @Published public private(set) var relayLastError: String?

    public enum RelayLight {
        case red, yellow, green
    }

    public let radroots: Radroots
    public let keys: RadrootsKeys

    private var statusTask: Task<Void, Never>?

    public init(radroots: Radroots = Radroots(), keys: RadrootsKeys = RadrootsKeys()) {
        self.radroots = radroots
        self.keys = keys
    }

    deinit {
        statusTask?.cancel()
    }

    public func start() throws {
        try radroots.start()
        if let rt = radroots.runtime {
            keys.loadFromKeychainIfPresent(runtime: rt)
            if rt.keysIsLoaded() {
                try? rt.nostrSetDefaultRelays(relays: ["wss://relay.damus.io"])
                try? rt.nostrConnectIfKeyPresent()
                startPollingStatus()
            }
        }
        refresh()
    }

    public func refresh() {
        guard let rt = radroots.runtime else { return }
        self.infoJSONString = rt.infoJson()
        self.hasKey = rt.keysIsLoaded()
        self.npub = rt.keysNpub()
        updateStatus()
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
        self.relayConnectedCount = s.connected
        self.relayConnectingCount = s.connecting
        self.relayLastError = s.lastError
        switch s.light {
        case .green: self.relayLight = .green
        case .yellow: self.relayLight = .yellow
        case .red: self.relayLight = .red
        @unknown default: self.relayLight = .red
        }
    }
}
