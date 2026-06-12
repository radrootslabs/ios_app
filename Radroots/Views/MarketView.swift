import SwiftUI

@MainActor
final class TradeListingsViewModel: ObservableObject {
    @Published var listings: [TradeListingSummary] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var searchText: String = ""

    func loadIfNeeded(app: AppState) async {
        if listings.isEmpty {
            await refresh(app: app)
        }
    }

    func refresh(app: AppState) async {
        guard let service = app.runtimeService else { return }
        isLoading = true
        errorMessage = nil

        do {
            let items = try await service.tradeListingsFetch(limit: 60, sinceUnix: nil)
            listings = items
            isLoading = false
        } catch {
            errorMessage = String(describing: error)
            isLoading = false
        }
    }
}

struct MarketView: View {
    @EnvironmentObject private var app: AppState
    @StateObject private var vm = TradeListingsViewModel()
    @State private var showCreate = false

    var body: some View {
        List {
            if let error = vm.errorMessage {
                Section {
                    Text(error)
                        .foregroundStyle(.red)
                        .font(.footnote)
                }
            }

            if filteredListings.isEmpty {
                if vm.isLoading {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                    .listRowBackground(Color.clear)
                } else {
                    ContentUnavailableView(
                        "No Listings Yet",
                        systemImage: "leaf",
                        description: Text("Connect to relays and pull listings from the network.")
                    )
                    .listRowBackground(Color.clear)
                }
            } else {
                Section {
                    ForEach(filteredListings) { listing in
                        NavigationLink {
                            TradeListingDetailView(listing: listing)
                        } label: {
                            TradeListingRow(listing: listing)
                        }
                    }
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle("Market")
        .accessibilityIdentifier("field_ios.market")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if vm.isLoading {
                    ProgressView()
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showCreate = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .searchable(text: $vm.searchText, placement: .navigationBarDrawer(displayMode: .always))
        .task { await vm.loadIfNeeded(app: app) }
        .refreshable { await vm.refresh(app: app) }
        .sheet(isPresented: $showCreate) {
            NavigationStack {
                TradeListingCreateView {
                    Task { await vm.refresh(app: app) }
                }
            }
        }
    }

    private var filteredListings: [TradeListingSummary] {
        let trimmed = vm.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return vm.listings }
        let needle = trimmed.lowercased()
        return vm.listings.filter { listing in
            let haystack = [
                listing.title,
                listing.description,
                listing.productType,
                listing.location,
                listing.sellerPubkey
            ]
                .joined(separator: " ")
                .lowercased()
            return haystack.contains(needle)
        }
    }
}

private struct TradeListingRow: View {
    let listing: TradeListingSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(listing.title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Spacer()
                Text(listing.availability.capitalized)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            if !listing.description.isEmpty {
                Text(listing.description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            HStack {
                Text(priceLine)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Spacer()
                Text("Inventory \(listing.inventoryAvailable)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Text(binLine)
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                Label(listing.deliveryMethod.capitalized, systemImage: "truck.box")
                Label(listing.location, systemImage: "mappin.and.ellipse")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
        .padding(.vertical, 4)
    }

    private var priceLine: String {
        "\(listing.unitPriceAmount) \(listing.unitPriceCurrency) / \(listing.unitPriceUnit)"
    }

    private var binLine: String {
        let label = listing.binDisplayLabel?.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = "Bin \(listing.binDisplayAmount) \(listing.binDisplayUnit)"
        if let label, !label.isEmpty {
            return "\(base) \(label)"
        }
        return base
    }
}
