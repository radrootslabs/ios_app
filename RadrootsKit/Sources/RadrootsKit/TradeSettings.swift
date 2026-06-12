import Foundation

public enum TradeSettingsError: LocalizedError {
    case noRhiPubkeyConfigured

    public var errorDescription: String? {
        "No trade RHI pubkey configured. Set 'RADROOTS_FIELD_IOS_TRADE_RHI_PUBKEY'."
    }
}

public enum TradeSettings {
    public static func rhiPubkey() throws -> String {
        guard let value = rhiPubkeyOptional else {
            throw TradeSettingsError.noRhiPubkeyConfigured
        }
        return value
    }

    public static var rhiPubkeyOptional: String? {
        BuildConfig.string(.tradeRhiPubkey)
            .flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .flatMap { $0.isEmpty ? nil : $0 }
    }
}
