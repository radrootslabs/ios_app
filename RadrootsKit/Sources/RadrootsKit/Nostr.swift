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

public enum RadrootsRuntimeError: LocalizedError {
    case runtimeNotStarted

    public var errorDescription: String? {
        "Radroots runtime not started."
    }
}

@MainActor
public extension Radroots {
    func nostrPostProfile(
        name: String? = nil,
        displayName: String? = nil,
        nip05: String? = nil,
        about: String? = nil
    ) throws -> NostrEventId {
        let rt = try requireRuntime()
        let id = try rt.nostrPostProfile(
            name: name,
            displayName: displayName,
            nip05: nip05,
            about: about
        )
        return NostrEventId(id)
    }

    func nostrPostTextNote(content: String) throws -> NostrEventId {
        let rt = try requireRuntime()
        let id = try rt.nostrPostTextNote(content: content)
        return NostrEventId(id)
    }

    func nostrPostReply(
        parentEventIdHex: String,
        parentAuthorHex: String,
        content: String,
        rootEventIdHex: String? = nil
    ) throws -> NostrEventId {
        let rt = try requireRuntime()
        let id = try rt.nostrPostReply(
            parentEventIdHex: parentEventIdHex,
            parentAuthorHex: parentAuthorHex,
            content: content,
            rootEventIdHex: rootEventIdHex
        )
        return NostrEventId(id)
    }

    func nostrStartPostStream(sinceUnix: UInt64? = nil) throws {
        let rt = try requireRuntime()
        try rt.nostrStartPostEventStream(sinceUnix: sinceUnix)
    }

    func nostrNextPostStreamEvent() -> NostrPostEventMetadata? {
        guard let rt = runtime else { return nil }
        return rt.nostrNextPostEvent()
    }

    func nostrStopPostStream() throws {
        let rt = try requireRuntime()
        try rt.nostrStopPostEventStream()
    }
}

@MainActor
private extension Radroots {
    func requireRuntime() throws -> RadrootsRuntime {
        guard let rt = runtime else { throw RadrootsRuntimeError.runtimeNotStarted }
        return rt
    }
}
