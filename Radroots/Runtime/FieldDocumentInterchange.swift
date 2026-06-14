import Foundation
import RadrootsKit

enum FieldDocumentInterchangeError: LocalizedError, Equatable {
    case emptyRelayConfig
    case invalidRelayURL(String)
    case invalidRelayConfigDocument

    var errorDescription: String? {
        switch self {
        case .emptyRelayConfig:
            "Relay config must include at least one Nostr relay."
        case .invalidRelayURL(let value):
            "Invalid Nostr relay URL: \(value)."
        case .invalidRelayConfigDocument:
            "Relay config document is not valid JSON."
        }
    }
}

struct FieldRelayStatusDocument: Encodable, Equatable {
    let configuredRelays: [String]
    let connectedCount: UInt32
    let connectingCount: UInt32
    let lastError: String?
}

struct FieldRelayConfigDocument: Codable, Equatable {
    static let format = "radroots_field_ios_relay_config_v1"

    let format: String
    let relays: [String]

    init(relays: [String]) throws {
        self.format = Self.format
        self.relays = try FieldDocumentInterchange.validatedRelays(relays)
    }
}

struct FieldDiagnosticsDocument: Encodable, Equatable {
    let format: String
    let runtime: JSONValue
    let relay: FieldRelayStatusDocument
}

enum JSONValue: Encodable, Equatable {
    case object([String: JSONValue])
    case array([JSONValue])
    case string(String)
    case number(Double)
    case bool(Bool)
    case null

    init(jsonObject: Any) {
        switch jsonObject {
        case let object as [String: Any]:
            self = .object(object.mapValues(JSONValue.init(jsonObject:)))
        case let array as [Any]:
            self = .array(array.map(JSONValue.init(jsonObject:)))
        case let string as String:
            self = .string(string)
        case let number as NSNumber:
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                self = .bool(number.boolValue)
            } else {
                self = .number(number.doubleValue)
            }
        case _ as NSNull:
            self = .null
        default:
            self = .string(String(describing: jsonObject))
        }
    }

    func encode(to encoder: Encoder) throws {
        switch self {
        case .object(let object):
            try object.encode(to: encoder)
        case .array(let array):
            try array.encode(to: encoder)
        case .string(let string):
            try string.encode(to: encoder)
        case .number(let number):
            try number.encode(to: encoder)
        case .bool(let bool):
            try bool.encode(to: encoder)
        case .null:
            var container = encoder.singleValueContainer()
            try container.encodeNil()
        }
    }
}

final class FieldDocumentInterchange {
    private let fileAccess: RadrootsAppleFileAccess
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(bundleIdentifier: String) throws {
        self.fileAccess = try FieldLocalState.fileAccess(bundleIdentifier: bundleIdentifier)
        self.encoder = JSONEncoder()
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.decoder = JSONDecoder()
    }

    func prepareDiagnosticsExport(
        infoJSONString: String,
        relays: [String],
        connectedCount: UInt32,
        connectingCount: UInt32,
        lastError: String?
    ) throws -> RadrootsPreparedExportDocument {
        let document = FieldDiagnosticsDocument(
            format: "radroots_field_ios_diagnostics_v1",
            runtime: Self.jsonValue(from: infoJSONString),
            relay: FieldRelayStatusDocument(
                configuredRelays: try Self.validatedRelays(relays),
                connectedCount: connectedCount,
                connectingCount: connectingCount,
                lastError: lastError
            )
        )
        return try prepareJSONExport(data: encoder.encode(document), filename: "radroots-diagnostics.json")
    }

    func prepareRelayConfigExport(relays: [String]) throws -> RadrootsPreparedExportDocument {
        let document = try FieldRelayConfigDocument(relays: relays)
        return try prepareJSONExport(data: encoder.encode(document), filename: "radroots-relays.json")
    }

    func importedRelayConfig(from importedDocument: RadrootsImportedDocument) throws -> [String] {
        try importedRelayConfig(from: importedDocument.file)
    }

    func importedRelayConfig(from file: RadrootsFileReference) throws -> [String] {
        let result = try fileAccess.read(file, mode: .inline)
        guard case .inline(let data) = result else {
            throw FieldDocumentInterchangeError.invalidRelayConfigDocument
        }
        let document = try decoder.decode(FieldRelayConfigDocument.self, from: data)
        guard document.format == FieldRelayConfigDocument.format else {
            throw FieldDocumentInterchangeError.invalidRelayConfigDocument
        }
        return try Self.validatedRelays(document.relays)
    }

    func publicPostShareRequest(content: String) throws -> RadrootsShareRequest {
        try RadrootsShareRequest(items: [.text(content)], subject: "Radroots")
    }

    static func validatedRelays(_ relays: [String]) throws -> [String] {
        var seen = Set<String>()
        var normalized: [String] = []
        for relay in relays {
            let trimmed = relay.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                continue
            }
            guard let components = URLComponents(string: trimmed),
                  let scheme = components.scheme?.lowercased(),
                  scheme == "ws" || scheme == "wss",
                  components.host != nil,
                  trimmed.rangeOfCharacter(from: .whitespacesAndNewlines) == nil else {
                throw FieldDocumentInterchangeError.invalidRelayURL(relay)
            }
            let key = trimmed.lowercased()
            if seen.insert(key).inserted {
                normalized.append(trimmed)
            }
        }
        guard !normalized.isEmpty else {
            throw FieldDocumentInterchangeError.emptyRelayConfig
        }
        return normalized
    }

    private func prepareJSONExport(data: Data, filename: String) throws -> RadrootsPreparedExportDocument {
        try fileAccess.prepareExport(
            RadrootsExportDocumentRequest(
                source: .inlineData(data),
                suggestedFilename: filename,
                mediaType: "application/json"
            )
        )
    }

    private static func jsonValue(from string: String) -> JSONValue {
        guard let data = string.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) else {
            return .string(string)
        }
        return JSONValue(jsonObject: object)
    }
}
