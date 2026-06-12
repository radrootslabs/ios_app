import Foundation

public extension FieldRuntimeService {
    func tradeListingPublish(draft: TradeListingDraft) async throws -> NostrEventId {
        let id = try await run { try $0.tradeListingPublish(draft: draft) }
        return NostrEventId(id)
    }

    func tradeListingsFetch(limit: UInt16, sinceUnix: UInt64? = nil) async throws -> [TradeListingSummary] {
        try await run { try $0.tradeListingsFetch(limit: limit, sinceUnix: sinceUnix) }
    }

    func tradeListingSendValidationRequest(
        listingEventId: String,
        sellerPubkey: String,
        listingId: String,
        recipientPubkey: String
    ) async throws -> NostrEventId {
        let id = try await run {
            try $0.tradeListingSendValidationRequest(
                listingEventId: listingEventId,
                sellerPubkey: sellerPubkey,
                listingId: listingId,
                recipientPubkey: recipientPubkey
            )
        }
        return NostrEventId(id)
    }

    func tradeListingSendOrderRequest(draft: TradeOrderDraft) async throws -> TradeOrderSendResult {
        try await run { try $0.tradeListingSendOrderRequest(draft: draft) }
    }

    func tradeListingFetchMessages(
        listingAddr: String,
        limit: UInt16,
        sinceUnix: UInt64? = nil
    ) async throws -> [TradeListingMessageSummary] {
        try await run {
            try $0.tradeListingFetchMessages(
                listingAddr: listingAddr,
                limit: limit,
                sinceUnix: sinceUnix
            )
        }
    }
}

extension TradeListingSummary: Identifiable {
    public var id: String { eventId }
}

extension TradeListingMessageSummary: Identifiable {
    public var id: String { eventId }
}
