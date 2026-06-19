import Foundation

public extension FieldRuntimeService {
    func tradeListingPublish(draft: TradeListingDraft) async throws -> NostrEventId {
        let id = try await run { try $0.tradeListingPublish(draft: draft) }
        return NostrEventId(id)
    }

    func tradeListingsFetch(limit: UInt16, sinceUnix: UInt64? = nil) async throws -> [TradeListingSummary] {
        try await run { try $0.tradeListingsFetch(limit: limit, sinceUnix: sinceUnix) }
    }

}

extension TradeListingSummary: Identifiable {
    public var id: String { eventId }
}
