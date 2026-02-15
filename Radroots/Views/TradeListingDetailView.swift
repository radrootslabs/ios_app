import SwiftUI
import RadrootsKit

@MainActor
final class TradeListingDetailViewModel: ObservableObject {
    let listing: TradeListingSummary
    @Published var messages: [TradeListingMessageSummary] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var orderId: String?

    init(listing: TradeListingSummary) {
        self.listing = listing
    }

    func refresh(app: AppState) async {
        guard let rt = app.radroots.runtime else { return }
        isLoading = true
        errorMessage = nil

        let listingAddr = listing.listingAddr
        let orderId = self.orderId

        let result: Result<[TradeListingMessageSummary], Error> = await Task.detached { @Sendable in
            do {
                return .success(
                    try rt.tradeListingFetchMessages(
                        listingAddr: listingAddr,
                        orderId: orderId,
                        limit: 80,
                        sinceUnix: nil
                    )
                )
            } catch {
                return .failure(error)
            }
        }.value

        switch result {
        case .success(let items):
            messages = items
            isLoading = false
        case .failure(let error):
            errorMessage = String(describing: error)
            isLoading = false
        }
    }
}

struct TradeListingDetailView: View {
    @EnvironmentObject private var app: AppState
    let listing: TradeListingSummary
    @StateObject private var vm: TradeListingDetailViewModel
    @State private var showOrderSheet = false
    @State private var showValidationAlert = false
    @State private var validationMessage = ""

    init(listing: TradeListingSummary) {
        self.listing = listing
        _vm = StateObject(wrappedValue: TradeListingDetailViewModel(listing: listing))
    }

    var body: some View {
        List {
            Section("Listing") {
                LabeledContent("Title", value: listing.title)
                if !listing.description.isEmpty {
                    LabeledContent("Description", value: listing.description)
                }
                LabeledContent("Category", value: listing.productType)
                if !listing.availability.isEmpty {
                    LabeledContent("Availability", value: listing.availability.capitalized)
                }
            }

            Section("Pricing") {
                LabeledContent("Unit price", value: priceLine)
                LabeledContent("Bin size", value: binLine)
                LabeledContent("Inventory", value: listing.inventoryAvailable)
            }

            Section("Delivery") {
                LabeledContent("Method", value: listing.deliveryMethod.capitalized)
                LabeledContent("Location", value: listing.location)
            }

            Section {
                SectionWideButton("Validate Listing", enabled: canUseTrade) {
                    sendValidationRequest()
                }

                SectionWideButton("Request Order", enabled: canUseTrade, isProminent: true) {
                    showOrderSheet = true
                }

                if let orderId = vm.orderId {
                    LabeledContent("Order ID", value: orderId)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Actions")
            } footer: {
                if !canUseTrade {
                    Text(tradeDisabledMessage)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Activity") {
                if let error = vm.errorMessage {
                    Text(error)
                        .foregroundStyle(.red)
                        .font(.footnote)
                }

                if vm.messages.isEmpty {
                    ContentUnavailableView(
                        "No Activity Yet",
                        systemImage: "bubble.left.and.text.bubble.right",
                        description: Text("Validation and order updates appear here.")
                    )
                    .listRowBackground(Color.clear)
                } else {
                    ForEach(vm.messages) { message in
                        TradeListingMessageRow(message: message)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .inlineNavigationTitle(listing.title)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if vm.isLoading { ProgressView() }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await vm.refresh(app: app) }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
            }
        }
        .task { await vm.refresh(app: app) }
        .refreshable { await vm.refresh(app: app) }
        .sheet(isPresented: $showOrderSheet) {
            NavigationStack {
                TradeOrderRequestView(listing: listing) { result in
                    vm.orderId = result.orderId
                    Task { await vm.refresh(app: app) }
                }
            }
        }
        .alert("Validation Request", isPresented: $showValidationAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(validationMessage)
        }
    }

    private var priceLine: String {
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

    private var canUseTrade: Bool {
        app.relayConnectedCount > 0 && TradeSettings.rhiPubkeyOptional != nil
    }

    private var tradeDisabledMessage: String {
        if app.relayConnectedCount == 0 {
            return "Connect to relays to use trade flows."
        }
        return "Set RR_TRADE_RHI_PUBKEY to enable trade requests."
    }

    private func sendValidationRequest() {
        guard let rt = app.radroots.runtime else { return }
        guard let rhiPubkey = TradeSettings.rhiPubkeyOptional else {
            validationMessage = "Set RR_TRADE_RHI_PUBKEY to enable validation."
            showValidationAlert = true
            return
        }

        Task { @MainActor in
            let result: Result<String, Error> = await Task.detached { @Sendable in
                do {
                    return .success(
                        try rt.tradeListingSendValidationRequest(
                            listingEventId: listing.eventId,
                            sellerPubkey: listing.sellerPubkey,
                            listingId: listing.listingId,
                            recipientPubkey: rhiPubkey
                        )
                    )
                } catch {
                    return .failure(error)
                }
            }.value

            switch result {
            case .success(let id):
                validationMessage = "Validation request sent: \(id)"
            case .failure(let error):
                validationMessage = "Validation failed: \(error)"
            }
            showValidationAlert = true
        }
    }
}

private struct TradeListingMessageRow: View {
    let message: TradeListingMessageSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(message.summary)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
            HStack {
                Text(message.messageType.replacingOccurrences(of: "_", with: " ").capitalized)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(relativeTime(message.publishedAt))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private func relativeTime(_ unix: UInt64) -> String {
        let d = Date(timeIntervalSince1970: TimeInterval(unix))
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f.localizedString(for: d, relativeTo: Date())
    }
}
