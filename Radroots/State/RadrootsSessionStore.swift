import Foundation
import RadrootsKit
import UIKit

final class RadrootsProtectedDataMonitor: @unchecked Sendable {
    private let lock = NSLock()
    private var available: Bool

    init(available: Bool) {
        self.available = available
    }

    func update(available: Bool) {
        lock.withLock { self.available = available }
    }

    func isAvailable() -> Bool {
        lock.withLock { available }
    }
}

enum RadrootsSessionPhase: Sendable, Equatable {
    case starting
    case identityRequired
    case identityLocked(RadrootsAppIdentity)
    case protectedDataUnavailable(RadrootsAppIdentity)
    case recoveryRequired(RadrootsAppIdentity)
    case corruptIdentity(RadrootsAppIdentity)
    case running(RadrootsRuntimeSnapshot)
    case stopped
    case failed(RadrootsRuntimeFailure)
}

actor RadrootsSessionStore {
    private let configurationStore: RadrootsConfigurationStore
    private let identityStore: RadrootsIdentityStore
    private let runtimeClient: RadrootsRuntimeClient
    private let roots: RadrootsAppleFileRoots
    private let protectedData: RadrootsProtectedDataMonitor
    private var generation: UInt64 = 0
    private var phase: RadrootsSessionPhase = .starting

    init(
        configurationStore: RadrootsConfigurationStore,
        identityStore: RadrootsIdentityStore,
        runtimeClient: RadrootsRuntimeClient,
        roots: RadrootsAppleFileRoots,
        protectedData: RadrootsProtectedDataMonitor
    ) {
        self.configurationStore = configurationStore
        self.identityStore = identityStore
        self.runtimeClient = runtimeClient
        self.roots = roots
        self.protectedData = protectedData
    }

    @MainActor
    static func production(
        bundle: Bundle = .main,
        runtimeClient: RadrootsRuntimeClient = .production()
    ) throws -> RadrootsSessionStore {
        guard let bundleIdentifier = bundle.bundleIdentifier else {
            throw RadrootsConfigurationError.missing("bundle_identifier")
        }
        let servicePrefix = try requiredString(
            "RADROOTS_FIELD_IOS_KEYCHAIN_SERVICE_PREFIX",
            bundle: bundle
        )
        let bootstrap = try RadrootsConfigurationBootstrap(
            runtimeMode: requiredString("RADROOTS_FIELD_IOS_RUNTIME_MODE", bundle: bundle),
            relayURLs: array("RADROOTS_FIELD_IOS_NOSTR_RELAY_URLS", bundle: bundle),
            blossomOrigins: array("RADROOTS_FIELD_IOS_BLOSSOM_ORIGINS", bundle: bundle),
            keychainServicePrefix: servicePrefix,
            bundleIdentifier: bundleIdentifier,
            appMetadata: RadrootsRuntimeAppMetadata(
                bundleIdentifier: bundleIdentifier,
                version: bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0",
                buildNumber: bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0",
                buildSHA: normalizedOptional(
                    bundle.object(forInfoDictionaryKey: "GIT_SHA") as? String
                )
            )
        )
        let roots = try RadrootsAppleFileRoots.appContainer(appIdentifier: bundleIdentifier)
        let protectedData = RadrootsProtectedDataMonitor(
            available: UIApplication.shared.isProtectedDataAvailable
        )
        return try RadrootsSessionStore(
            configurationStore: RadrootsConfigurationStore(bootstrap: bootstrap, roots: roots),
            identityStore: .production(
                servicePrefix: servicePrefix,
                protectedDataAvailable: { protectedData.isAvailable() }
            ),
            runtimeClient: runtimeClient,
            roots: roots,
            protectedData: protectedData
        )
    }

    func updateProtectedDataAvailability(_ available: Bool) {
        protectedData.update(available: available)
    }

    func currentPhase() -> RadrootsSessionPhase {
        phase
    }

    func start() async -> RadrootsSessionPhase {
        generation &+= 1
        let requestedGeneration = generation
        phase = .starting
        do {
            let identity = try await identityStore.loadAndMigrate()
            guard generation == requestedGeneration else {
                throw RadrootsRuntimeClientError.superseded
            }
            switch identity.state {
            case .absent:
                phase = .identityRequired
            case .locked:
                phase = .identityLocked(identity)
            case .protectedDataUnavailable:
                phase = .protectedDataUnavailable(identity)
            case .recoveryRequired:
                phase = .recoveryRequired(identity)
            case .corrupt:
                phase = .corruptIdentity(identity)
            case .unlocked:
                let configuration = try await configurationStore.load()
                phase = try await startRuntime(
                    configuration: configuration,
                    identity: identity,
                    generation: requestedGeneration
                )
            }
        } catch RadrootsRuntimeClientError.superseded {
            return phase
        } catch let RadrootsRuntimeClientError.startup(failure) {
            guard generation == requestedGeneration else { return phase }
            phase = .failed(failure)
        } catch let error as LocalizedError {
            guard generation == requestedGeneration else { return phase }
            phase = .failed(
                .local(
                    operation: "session.start",
                    code: "ios.session.start_failed",
                    safeMessage: error.errorDescription ?? "Radroots could not start."
                )
            )
        } catch {
            guard generation == requestedGeneration else { return phase }
            phase = .failed(
                .local(
                    operation: "session.start",
                    code: "ios.session.start_failed",
                    safeMessage: "Radroots could not start."
                )
            )
        }
        return phase
    }

    func createIdentity(label: String? = nil) async -> RadrootsSessionPhase {
        do {
            _ = try await identityStore.create(label: label)
        } catch {
            return failIdentityOperation(error)
        }
        return await start()
    }

    func importIdentity(_ text: String, label: String? = nil) async -> RadrootsSessionPhase {
        do {
            _ = try await identityStore.importIdentity(text, label: label)
        } catch {
            return failIdentityOperation(error)
        }
        return await start()
    }

    func unlockIdentity() async -> RadrootsSessionPhase {
        do {
            _ = try await identityStore.unlock()
        } catch {
            return failIdentityOperation(error)
        }
        return await start()
    }

    func recoverIdentity() async -> RadrootsSessionPhase {
        do {
            _ = try await identityStore.recover()
        } catch {
            return failIdentityOperation(error)
        }
        return await start()
    }

    func stop() async -> RadrootsSessionPhase {
        generation &+= 1
        do {
            _ = try await runtimeClient.stop()
            await identityStore.lock()
            phase = .stopped
        } catch let RadrootsRuntimeClientError.shutdown(failure) {
            phase = .failed(failure)
        } catch {
            phase = .failed(
                .local(
                    operation: "session.stop",
                    code: "ios.session.stop_failed",
                    safeMessage: "Radroots could not finish shutting down."
                )
            )
        }
        return phase
    }

    private func startRuntime(
        configuration: RadrootsAppConfiguration,
        identity: RadrootsAppIdentity,
        generation requestedGeneration: UInt64
    ) async throws -> RadrootsSessionPhase {
        guard let publicKeyHex = identity.publicKeyHex,
              let signerGeneration = identity.signerGeneration
        else {
            throw RadrootsIdentityStoreError.unavailable
        }
        let mobileStore = try RadrootsAppleMobileStore.prepare(
            roots: roots,
            publicKeyHex: publicKeyHex,
            protectedDataAvailability: protectedData.isAvailable() ? .available : .unavailable
        )
        let sourceGeneration = try await configurationStore.sourceGeneration()
        let signer = try await identityStore.signer(for: identity)
        let snapshot = try await runtimeClient.start(
            configuration: RadrootsRuntimeLaunchConfiguration(
                applicationSupportDirectory: mobileStore.applicationSupportDirectory.path,
                publicKeyHex: publicKeyHex,
                sourceGenerationHex: sourceGeneration.generationHex,
                sourceGenerationCreatedAtUnixMilliseconds: sourceGeneration.createdAtUnixMilliseconds,
                protectedData: protectedData.isAvailable() ? .available : .unavailable,
                networkProfile: configuration.profile.runtimeValue,
                writableRelays: configuration.writableRelays,
                blossomOrigins: configuration.blossomOrigins,
                app: configuration.appMetadata,
                signerGeneration: signerGeneration,
                signer: signer
            )
        )
        guard generation == requestedGeneration else {
            _ = try? await runtimeClient.stop()
            throw RadrootsRuntimeClientError.superseded
        }
        return .running(snapshot)
    }

    private func failIdentityOperation(_ error: Error) -> RadrootsSessionPhase {
        generation &+= 1
        let message = (error as? LocalizedError)?.errorDescription
            ?? "The local identity operation could not be completed."
        phase = .failed(
            .local(
                operation: "identity.operation",
                code: "ios.identity.operation_failed",
                safeMessage: message
            )
        )
        return phase
    }

    @MainActor
    private static func requiredString(_ key: String, bundle: Bundle) throws -> String {
        guard let value = normalizedOptional(bundle.object(forInfoDictionaryKey: key) as? String) else {
            throw RadrootsConfigurationError.missing(key)
        }
        return value
    }

    @MainActor
    private static func array(_ key: String, bundle: Bundle) -> [String] {
        if let values = bundle.object(forInfoDictionaryKey: key) as? [String] {
            return values.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }
        guard let raw = normalizedOptional(bundle.object(forInfoDictionaryKey: key) as? String) else {
            return []
        }
        return raw.components(separatedBy: CharacterSet(charactersIn: ",; \n\r\t"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    @MainActor
    private static func normalizedOptional(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty || trimmed == "unknown" ? nil : trimmed
    }
}
