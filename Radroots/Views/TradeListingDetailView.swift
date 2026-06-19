import SwiftUI

struct TradeListingDetailView: View {
    let listing: TradeListingSummary

    init(listing: TradeListingSummary) {
        self.listing = listing
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
                CopyRow(title: "Listing ID", value: listing.listingId)
                CopyRow(title: "Event ID", value: listing.eventId)
                CopyRow(title: "Seller", value: listing.sellerPubkey)
            } header: {
                Text("Event")
            }
        }
        .listStyle(.insetGrouped)
        .inlineNavigationTitle(listing.title)
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

}
