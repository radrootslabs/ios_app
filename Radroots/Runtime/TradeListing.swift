import Foundation

@MainActor
public extension Radroots {
    func tradeListingPublish(draft: TradeListingDraft) throws -> NostrEventId {
        let rt = try requireRuntime()
        let id = try rt.tradeListingPublish(draft: draft)
        return NostrEventId(id)
    }

    func tradeListingsFetch(limit: UInt16, sinceUnix: UInt64? = nil) throws -> [TradeListingSummary] {
        let rt = try requireRuntime()
        return try rt.tradeListingsFetch(limit: limit, sinceUnix: sinceUnix)
    }

    func tradeListingSendValidationRequest(
        listingEventId: String,
        sellerPubkey: String,
        listingId: String,
        recipientPubkey: String
    ) throws -> NostrEventId {
        let rt = try requireRuntime()
        let id = try rt.tradeListingSendValidationRequest(
            listingEventId: listingEventId,
            sellerPubkey: sellerPubkey,
            listingId: listingId,
            recipientPubkey: recipientPubkey
        )
        return NostrEventId(id)
    }

    func tradeListingSendOrderRequest(draft: TradeOrderDraft) throws -> TradeOrderSendResult {
        let rt = try requireRuntime()
        return try rt.tradeListingSendOrderRequest(draft: draft)
    }

    func tradeListingFetchMessages(
        listingAddr: String,
        limit: UInt16,
        sinceUnix: UInt64? = nil
    ) throws -> [TradeListingMessageSummary] {
        let rt = try requireRuntime()
        return try rt.tradeListingFetchMessages(
            listingAddr: listingAddr,
            limit: limit,
            sinceUnix: sinceUnix
        )
    }
}

extension TradeListingSummary: Identifiable {
    public var id: String { eventId }
}

extension TradeListingMessageSummary: Identifiable {
    public var id: String { eventId }
}
