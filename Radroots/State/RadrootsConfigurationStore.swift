import Darwin
import Foundation
import RadrootsKit
import Security

enum RadrootsAppNetworkProfile: String, Codable, Sendable, Equatable {
    case publicNetwork = "public"
    case simulator
    case device

    var runtimeValue: RadrootsRuntimeNetworkProfile {
        switch self {
        case .publicNetwork: .publicNetwork
        case .simulator: .simulator
        case .device: .device
        }
    }
}

struct RadrootsAppConfiguration: Sendable, Equatable {
    let profile: RadrootsAppNetworkProfile
    let writableRelays: [String]
    let blossomOrigins: [String]
    let keychainServicePrefix: String
    let bundleIdentifier: String
    let appMetadata: RadrootsRuntimeAppMetadata
}

struct RadrootsConfigurationBootstrap: Sendable, Equatable {
    let runtimeMode: String
    let relayURLs: [String]
    let blossomOrigins: [String]
    let keychainServicePrefix: String
    let bundleIdentifier: String
    let appMetadata: RadrootsRuntimeAppMetadata
}

struct RadrootsSourceGeneration: Codable, Sendable, Equatable {
    let schemaVersion: UInt16
    let generationHex: String
    let createdAtUnixMilliseconds: UInt64
}

enum RadrootsConfigurationError: Error, Sendable, Equatable {
    case missing(String)
    case invalid(String)
    case corruptStoredConfiguration
    case corruptSourceGeneration
    case persistenceFailed
}

extension RadrootsConfigurationError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .missing:
            "Required Radroots configuration is missing."
        case .invalid:
            "Radroots network configuration is invalid."
        case .corruptStoredConfiguration:
            "Stored Radroots settings are corrupt and require recovery."
        case .corruptSourceGeneration:
            "Stored Radroots local-state identity is corrupt and requires recovery."
        case .persistenceFailed:
            "Radroots could not persist its local configuration."
        }
    }
}

actor RadrootsConfigurationStore {
    private struct StoredConfiguration: Codable {
        static let format = "radroots_ios_configuration_v2"

        let format: String
        let profile: RadrootsAppNetworkProfile
        let writableRelays: [String]
        let blossomOrigins: [String]
    }

    private struct LegacyRelaySettings: Codable {
        static let format = "radroots_field_ios_relay_settings_v1"

        let format: String
        let relays: [String]
    }

    private static let configurationFile = RadrootsFileReference(
        scope: .data,
        relativePath: "settings/radroots_configuration_v2.json"
    )
    private static let legacyRelayFile = RadrootsFileReference(
        scope: .data,
        relativePath: "settings/relay_settings.json"
    )
    private static let sourceGenerationFile = RadrootsFileReference(
        scope: .data,
        relativePath: "state/source_generation_v1.json"
    )

    private let bootstrap: RadrootsConfigurationBootstrap
    private let fileAccess: RadrootsAppleFileAccess

    init(bootstrap: RadrootsConfigurationBootstrap, roots: RadrootsAppleFileRoots) {
        self.bootstrap = bootstrap
        fileAccess = RadrootsAppleFileAccess(roots: roots)
    }

    func load() throws -> RadrootsAppConfiguration {
        let profile = try Self.profile(for: bootstrap.runtimeMode)
        let stored = try readStoredConfiguration()
        let selected: StoredConfiguration
        if let stored {
            guard stored.format == StoredConfiguration.format, stored.profile == profile else {
                throw RadrootsConfigurationError.corruptStoredConfiguration
            }
            selected = stored
        } else if let legacy = try readLegacyConfiguration() {
            guard legacy.format == LegacyRelaySettings.format else {
                throw RadrootsConfigurationError.corruptStoredConfiguration
            }
            selected = StoredConfiguration(
                format: StoredConfiguration.format,
                profile: profile,
                writableRelays: legacy.relays,
                blossomOrigins: bootstrap.blossomOrigins
            )
            try persist(selected)
        } else {
            selected = StoredConfiguration(
                format: StoredConfiguration.format,
                profile: profile,
                writableRelays: bootstrap.relayURLs,
                blossomOrigins: bootstrap.blossomOrigins
            )
        }

        let relays = try RadrootsNetworkValidator.relays(
            selected.writableRelays,
            profile: profile
        )
        let origins = try RadrootsNetworkValidator.blossomOrigins(
            selected.blossomOrigins,
            profile: profile
        )
        guard !bootstrap.keychainServicePrefix.isEmpty,
              !bootstrap.bundleIdentifier.isEmpty
        else {
            throw RadrootsConfigurationError.missing("identity")
        }
        return RadrootsAppConfiguration(
            profile: profile,
            writableRelays: relays,
            blossomOrigins: origins,
            keychainServicePrefix: bootstrap.keychainServicePrefix,
            bundleIdentifier: bootstrap.bundleIdentifier,
            appMetadata: bootstrap.appMetadata
        )
    }

    func sourceGeneration() throws -> RadrootsSourceGeneration {
        if let data = try read(Self.sourceGenerationFile) {
            guard let value = try? JSONDecoder().decode(RadrootsSourceGeneration.self, from: data),
                  value.schemaVersion == 1,
                  value.generationHex.count == 64,
                  value.generationHex.allSatisfy(\.isHexDigit),
                  value.generationHex == value.generationHex.lowercased(),
                  value.createdAtUnixMilliseconds > 0
            else {
                throw RadrootsConfigurationError.corruptSourceGeneration
            }
            return value
        }
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            throw RadrootsConfigurationError.persistenceFailed
        }
        let value = RadrootsSourceGeneration(
            schemaVersion: 1,
            generationHex: bytes.map { String(format: "%02x", $0) }.joined(),
            createdAtUnixMilliseconds: max(1, UInt64(Date().timeIntervalSince1970 * 1000))
        )
        do {
            let data = try JSONEncoder.radroots.encode(value)
            try fileAccess.write(.inline(data), to: Self.sourceGenerationFile)
            return value
        } catch let error as RadrootsConfigurationError {
            throw error
        } catch {
            throw RadrootsConfigurationError.persistenceFailed
        }
    }

    private func readStoredConfiguration() throws -> StoredConfiguration? {
        guard let data = try read(Self.configurationFile) else { return nil }
        guard let stored = try? JSONDecoder().decode(StoredConfiguration.self, from: data) else {
            throw RadrootsConfigurationError.corruptStoredConfiguration
        }
        return stored
    }

    private func readLegacyConfiguration() throws -> LegacyRelaySettings? {
        guard let data = try read(Self.legacyRelayFile) else { return nil }
        guard let legacy = try? JSONDecoder().decode(LegacyRelaySettings.self, from: data) else {
            throw RadrootsConfigurationError.corruptStoredConfiguration
        }
        return legacy
    }

    private func read(_ file: RadrootsFileReference) throws -> Data? {
        do {
            guard case let .inline(data) = try fileAccess.read(file, mode: .inline) else {
                throw RadrootsConfigurationError.persistenceFailed
            }
            return data
        } catch RadrootsAppleFileError.notFound {
            return nil
        } catch let error as RadrootsConfigurationError {
            throw error
        } catch {
            throw RadrootsConfigurationError.persistenceFailed
        }
    }

    private func persist(_ configuration: StoredConfiguration) throws {
        do {
            let data = try JSONEncoder.radroots.encode(configuration)
            try fileAccess.write(.inline(data), to: Self.configurationFile)
        } catch {
            throw RadrootsConfigurationError.persistenceFailed
        }
    }

    private static func profile(for runtimeMode: String) throws -> RadrootsAppNetworkProfile {
        switch runtimeMode.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "production": .publicNetwork
        case "localhost-dev", "simulator": .simulator
        case "device-development", "device": .device
        default: throw RadrootsConfigurationError.invalid("runtime_mode")
        }
    }
}

enum RadrootsNetworkValidator {
    static let publicReadOnlyRelay = "wss://radroots.org"

    static func relays(
        _ values: [String],
        profile: RadrootsAppNetworkProfile
    ) throws -> [String] {
        var output: [String] = []
        var seen = Set<String>()
        for raw in values {
            let canonical = try relay(raw, profile: profile)
            if profile != .simulator, canonical == publicReadOnlyRelay {
                continue
            }
            guard seen.insert(canonical).inserted else {
                throw RadrootsConfigurationError.invalid("duplicate_relay")
            }
            output.append(canonical)
        }
        if profile != .publicNetwork, output.isEmpty {
            throw RadrootsConfigurationError.invalid("empty_relay_set")
        }
        let totalCount = output.count + (profile == .simulator ? 0 : 1)
        guard totalCount <= 64 else {
            throw RadrootsConfigurationError.invalid("too_many_relays")
        }
        return output
    }

    static func blossomOrigins(
        _ values: [String],
        profile: RadrootsAppNetworkProfile
    ) throws -> [String] {
        var output: [String] = []
        var seen = Set<String>()
        for raw in values {
            guard raw == raw.trimmingCharacters(in: .whitespacesAndNewlines),
                  raw.utf8.allSatisfy({ $0 < 128 }),
                  let components = URLComponents(string: raw),
                  components.user == nil,
                  components.password == nil,
                  components.query == nil,
                  components.fragment == nil,
                  components.path.isEmpty || components.path == "/",
                  let scheme = components.scheme?.lowercased(),
                  let host = components.host?.lowercased(),
                  components.port != 0
            else {
                throw RadrootsConfigurationError.invalid("blossom_origin")
            }
            guard scheme == "https" || scheme == "http" && profile == .simulator,
                  hostAllowed(host, profile: profile)
            else {
                throw RadrootsConfigurationError.invalid("blossom_policy")
            }
            var canonical = "\(scheme)://\(hostForURL(host))"
            if let port = components.port,
               !((scheme == "https" && port == 443) || (scheme == "http" && port == 80))
            {
                canonical += ":\(port)"
            }
            guard seen.insert(canonical).inserted else {
                throw RadrootsConfigurationError.invalid("duplicate_blossom_origin")
            }
            output.append(canonical)
        }
        guard output.count <= 8 else {
            throw RadrootsConfigurationError.invalid("too_many_blossom_origins")
        }
        return output
    }

    private static func relay(
        _ raw: String,
        profile: RadrootsAppNetworkProfile
    ) throws -> String {
        guard raw == raw.trimmingCharacters(in: .whitespacesAndNewlines),
              raw.utf8.count <= 2048,
              !raw.contains(where: { $0.isASCII && ($0.isWhitespace || $0.asciiValue ?? 32 < 32) }),
              !raw.contains("?"),
              !raw.contains("#"),
              !raw.contains("\\"),
              let components = URLComponents(string: raw),
              components.user == nil,
              components.password == nil,
              let scheme = components.scheme?.lowercased(),
              let host = components.host?.lowercased(),
              components.port != 0,
              components.path.isEmpty || components.path == "/"
        else {
            throw RadrootsConfigurationError.invalid("relay_url")
        }
        guard scheme == "wss" || scheme == "ws" && profile == .simulator,
              hostAllowed(host, profile: profile)
        else {
            throw RadrootsConfigurationError.invalid("relay_policy")
        }
        var canonical = "\(scheme)://\(hostForURL(host))"
        if let port = components.port,
           !((scheme == "wss" && port == 443) || (scheme == "ws" && port == 80))
        {
            canonical += ":\(port)"
        }
        return canonical
    }

    private static func hostForURL(_ host: String) -> String {
        host.contains(":") ? "[\(host)]" : host
    }

    private static func hostAllowed(
        _ host: String,
        profile: RadrootsAppNetworkProfile
    ) -> Bool {
        if profile == .simulator {
            return host == "localhost" || host == "127.0.0.1" || host == "::1"
        }
        if host == "localhost" || host.hasSuffix(".localhost") {
            return false
        }
        if let ipv4 = IPv4Address(host) {
            return profile == .publicNetwork ? ipv4.isPublic : ipv4.isTrustedDevice
        }
        if let ipv6 = IPv6Address(host) {
            return profile == .publicNetwork ? ipv6.isPublic : ipv6.isTrustedDevice
        }
        if profile == .device {
            return true
        }
        let normalized = host.trimmingCharacters(in: CharacterSet(charactersIn: "."))
        return normalized.contains(".")
            && !normalized.hasSuffix(".local")
            && !normalized.hasSuffix(".home.arpa")
    }
}

private struct IPv4Address {
    private var address = in_addr()

    init?(_ value: String) {
        guard inet_pton(AF_INET, value, &address) == 1 else { return nil }
    }

    var isTrustedDevice: Bool {
        var address = address
        let octets = withUnsafeBytes(of: &address.s_addr) { Array($0) }
        return octets[0] != 0 && octets[0] != 127 && !(224 ... 239).contains(octets[0])
            && octets != [255, 255, 255, 255]
    }

    var isPublic: Bool {
        var address = address
        let octets = withUnsafeBytes(of: &address.s_addr) { Array($0) }
        guard isTrustedDevice else { return false }
        return !(octets[0] == 10
            || octets[0] == 169 && octets[1] == 254
            || octets[0] == 172 && (16 ... 31).contains(octets[1])
            || octets[0] == 192 && octets[1] == 168
            || octets[0] == 100 && (64 ... 127).contains(octets[1])
            || octets[0] == 192 && octets[1] == 0 && octets[2] == 0
            || octets[0] == 192 && octets[1] == 0 && octets[2] == 2
            || octets[0] == 192 && octets[1] == 88 && octets[2] == 99
            || octets[0] == 198 && (octets[1] == 18 || octets[1] == 19)
            || octets[0] == 198 && octets[1] == 51 && octets[2] == 100
            || octets[0] == 203 && octets[1] == 0 && octets[2] == 113
            || octets[0] >= 240)
    }
}

private struct IPv6Address {
    private var address = in6_addr()

    init?(_ value: String) {
        guard inet_pton(AF_INET6, value, &address) == 1 else { return nil }
    }

    var isTrustedDevice: Bool {
        var address = address
        let bytes = withUnsafeBytes(of: &address) { Array($0) }
        let allZero = bytes.allSatisfy { $0 == 0 }
        let loopback = bytes.dropLast().allSatisfy { $0 == 0 } && bytes.last == 1
        let multicast = bytes.first == 0xFF
        return !allZero && !loopback && !multicast
    }

    var isPublic: Bool {
        var address = address
        let bytes = withUnsafeBytes(of: &address) { Array($0) }
        guard isTrustedDevice, bytes.count == 16 else { return false }
        let segment0 = UInt16(bytes[0]) << 8 | UInt16(bytes[1])
        let segment1 = UInt16(bytes[2]) << 8 | UInt16(bytes[3])
        return segment0 & 0xE000 == 0x2000
            && !(segment0 == 0x2001 && segment1 <= 0x01FF)
            && !(segment0 == 0x2001 && segment1 == 0x0DB8)
            && segment0 != 0x2002
            && !(segment0 == 0x3FFF && segment1 & 0xF000 == 0)
    }
}

private extension JSONEncoder {
    static var radroots: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}
