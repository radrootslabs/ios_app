import Foundation

public struct NostrEventId: Hashable, Sendable {
    public let rawValue: String

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }
}

public extension NostrPostEventMetadata {
    var eventId: NostrEventId {
        NostrEventId(id)
    }
}

public extension NostrProfileEventMetadata {
    var eventId: NostrEventId {
        NostrEventId(id)
    }
}

public extension FieldRuntimeService {
    func nostrPostProfile(
        name: String? = nil,
        displayName: String? = nil,
        nip05: String? = nil,
        about: String? = nil
    ) async throws -> NostrEventId {
        let id = try await runtime.nostrPostProfile(
            name: name,
            displayName: displayName,
            nip05: nip05,
            about: about
        )
        return NostrEventId(id)
    }

    func nostrPostTextNote(content: String) async throws -> NostrEventId {
        let id = try await runtime.nostrPostTextNote(content: content)
        return NostrEventId(id)
    }

    func nostrPostReply(
        parentEventIdHex: String,
        parentAuthorHex: String,
        content: String,
        rootEventIdHex: String? = nil
    ) async throws -> NostrEventId {
        let id = try await runtime.nostrPostReply(
            parentEventIdHex: parentEventIdHex,
            parentAuthorHex: parentAuthorHex,
            content: content,
            rootEventIdHex: rootEventIdHex
        )
        return NostrEventId(id)
    }
}
