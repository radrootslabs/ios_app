import Foundation

@MainActor
public final class RadrootsKeys: ObservableObject {
    @Published public private(set) var hasKey: Bool = false
    @Published public private(set) var npub: String?

    public init() {}

    public func loadFromRuntime(runtime: RadrootsRuntime) {
        refresh(runtime: runtime)
    }

    public func generateAndPersist(runtime: RadrootsRuntime) throws {
        _ = try runtime.accountsGenerate(label: "iOS", makeSelected: true)
        refresh(runtime: runtime)
    }

    public func importSecretHex(hex: String, runtime: RadrootsRuntime) throws {
        _ = try runtime.accountsImportSecret(secretKey: hex, label: "iOS", makeSelected: true)
        refresh(runtime: runtime)
    }

    public func refresh(runtime: RadrootsRuntime) {
        self.hasKey = runtime.accountsHasSelectedSigningIdentity()
        self.npub = runtime.accountsSelectedNpub()
    }
}
