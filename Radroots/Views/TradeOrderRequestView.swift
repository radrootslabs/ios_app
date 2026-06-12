import SwiftUI
import Foundation

struct TradeOrderRequestView: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.dismiss) private var dismiss
    let listing: TradeListingSummary
    private let onComplete: (TradeOrderSendResult) -> Void

    @State private var binCount: String
    @State private var notes: String = ""
    @State private var isSending = false
    @State private var errorMessage: String?
    @FocusState private var focused: Bool

    init(listing: TradeListingSummary, onComplete: @escaping (TradeOrderSendResult) -> Void) {
        self.listing = listing
        self.onComplete = onComplete
        _binCount = State(initialValue: "1")
    }

    var body: some View {
        Form {
            Section("Order") {
                TextField("Bin count", text: $binCount)
                    .keyboardType(.numberPad)
                    .focused($focused)
                LabeledContent("Bin size", value: binLine)
                LabeledContent("Unit price", value: unitPriceLine)
                if let total = totalPriceLine {
                    LabeledContent("Estimated total", value: total)
                }
            }

            Section("Notes") {
                TextEditor(text: $notes)
                    .frame(minHeight: 100)
            }

            Section {
                SectionWideButton("Send Order Request", enabled: canSend, isProminent: true) {
                    sendOrder()
                }
            } footer: {
                if let errorMessage {
                    Text(errorMessage).foregroundStyle(.red)
                } else if TradeSettings.rhiPubkeyOptional == nil {
                    Text("Set RADROOTS_FIELD_IOS_TRADE_RHI_PUBKEY to enable order requests.")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .inlineNavigationTitle("Order Request")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if isSending { ProgressView() }
            }
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { focused = false }
            }
        }
        .onAppear { focused = true }
    }

    private var unitPriceLine: String {
        "\(listing.unitPriceAmount) \(listing.unitPriceCurrency) / \(listing.unitPriceUnit)"
    }

    private var binLine: String {
        let label = listing.binDisplayLabel?.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = "\(listing.binDisplayAmount) \(listing.binDisplayUnit)"
        if let label, !label.isEmpty {
            return "\(base) \(label)"
        }
        return base
    }

    private var canSend: Bool {
        app.relayConnectedCount > 0 &&
        !isSending &&
        TradeSettings.rhiPubkeyOptional != nil &&
        parsedBinCount != nil
    }

    private var totalPriceLine: String? {
        guard let countValue = parsedBinCount,
              let unitPrice = Decimal(string: listing.unitPriceAmount),
              let binAmount = Decimal(string: listing.binDisplayAmount) else {
            return nil
        }
        let count = Decimal(Int(countValue))
        let total = count * unitPrice * binAmount
        return "\(total) \(listing.unitPriceCurrency)"
    }

    private func sendOrder() {
        guard let service = app.runtimeService else { return }
        guard let rhiPubkey = TradeSettings.rhiPubkeyOptional else {
            errorMessage = "Missing RHI pubkey."
            return
        }
        errorMessage = nil
        isSending = true

        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let countValue = parsedBinCount else {
            errorMessage = "Bin count must be a whole number."
            isSending = false
            return
        }
        let trimmedCount = String(countValue)
        let draft = TradeOrderDraft(
            listingAddr: listing.listingAddr,
            sellerPubkey: listing.sellerPubkey,
            binId: listing.primaryBinId,
            binCount: trimmedCount,
            notes: trimmedNotes.isEmpty ? nil : trimmedNotes,
            orderId: nil,
            recipientPubkey: rhiPubkey
        )

        Task { @MainActor in
            do {
                let out = try await service.tradeListingSendOrderRequest(draft: draft)
                isSending = false
                onComplete(out)
                dismiss()
            } catch {
                isSending = false
                errorMessage = String(describing: error)
            }
        }
    }

    private var parsedBinCount: UInt32? {
        UInt32(binCount.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}
