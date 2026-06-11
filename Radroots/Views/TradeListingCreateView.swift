import SwiftUI
import RadrootsKit

struct TradeListingCreateView: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.dismiss) private var dismiss
    private var onCreated: (() -> Void)?

    @State private var draft = ListingDraftState()
    @State private var isPosting = false
    @State private var errorMessage: String?
    @FocusState private var focusedField: Field?

    init(onCreated: (() -> Void)? = nil) {
        self.onCreated = onCreated
    }

    var body: some View {
        Form {
            Section("Farm") {
                TextField("Farm pubkey", text: $draft.farmPubkey)
                    .textInputAutocapitalization(.none)
                    .autocorrectionDisabled()
                    .submitLabel(.next)
                    .focused($focusedField, equals: .farmPubkey)
                    .onSubmit { focusedField = .farmDTag }

                TextField("Farm id", text: $draft.farmDTag)
                    .textInputAutocapitalization(.none)
                    .autocorrectionDisabled()
                    .submitLabel(.next)
                    .focused($focusedField, equals: .farmDTag)
                    .onSubmit { focusedField = .title }
            }

            Section("Listing") {
                TextField("Title", text: $draft.title)
                    .textInputAutocapitalization(.words)
                    .submitLabel(.next)
                    .focused($focusedField, equals: .title)
                    .onSubmit { focusedField = .description }

                TextEditor(text: $draft.description)
                    .frame(minHeight: 120)
                    .focused($focusedField, equals: .description)
            }

            Section("Product") {
                TextField("Category", text: $draft.category)
                    .textInputAutocapitalization(.words)
                    .submitLabel(.next)
                    .focused($focusedField, equals: .category)
                    .onSubmit { focusedField = .unitPrice }
            }

            Section("Pricing") {
                TextField("Unit price", text: $draft.unitPrice)
                    .keyboardType(.decimalPad)
                    .focused($focusedField, equals: .unitPrice)

                TextField("Currency", text: $draft.currency)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .focused($focusedField, equals: .currency)

                HStack {
                    TextField("Bin size", text: $draft.binDisplayAmount)
                        .keyboardType(.decimalPad)
                        .focused($focusedField, equals: .binDisplayAmount)
                    Picker("Unit", selection: $draft.binDisplayUnit) {
                        ForEach(ListingDraftState.UnitOption.allCases, id: \.self) { unit in
                            Text(unit.label).tag(unit)
                        }
                    }
                    .pickerStyle(.menu)
                }

                TextField("Bin label (optional)", text: $draft.binLabel)
                    .textInputAutocapitalization(.words)
                    .focused($focusedField, equals: .binLabel)

                TextField("Inventory available", text: $draft.inventory)
                    .keyboardType(.decimalPad)
                    .focused($focusedField, equals: .inventory)
            }

            Section("Delivery") {
                Picker("Method", selection: $draft.deliveryMethod) {
                    ForEach(ListingDraftState.DeliveryMethod.allCases, id: \.self) { method in
                        Text(method.label).tag(method)
                    }
                }

                TextField("Location", text: $draft.locationPrimary)
                    .textInputAutocapitalization(.words)
                    .focused($focusedField, equals: .locationPrimary)

                TextField("City", text: $draft.locationCity)
                    .textInputAutocapitalization(.words)
                    .focused($focusedField, equals: .locationCity)

                TextField("Region", text: $draft.locationRegion)
                    .textInputAutocapitalization(.words)
                    .focused($focusedField, equals: .locationRegion)

                TextField("Country", text: $draft.locationCountry)
                    .textInputAutocapitalization(.characters)
                    .focused($focusedField, equals: .locationCountry)
            }

            Section {
                SectionWideButton("Publish Listing", enabled: canPublish, isProminent: true) {
                    publish()
                }
            } footer: {
                if let errorMessage {
                    Text(errorMessage).foregroundStyle(.red)
                } else if app.relayConnectedCount == 0 {
                    Text("No relays connected. Configure relays before publishing.")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .inlineNavigationTitle("New Listing")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if isPosting { ProgressView() }
            }
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { focusedField = nil }
            }
        }
    }

    private var canPublish: Bool {
        app.relayConnectedCount > 0 && !isPosting && draft.isValid
    }

    private func publish() {
        guard let rt = app.radroots.runtime else { return }
        errorMessage = nil
        isPosting = true
        let draftValue = draft.toTradeListingDraft()

        Task { @MainActor in
            let result: Result<String, Error> = await Task.detached { @Sendable in
                do {
                    return .success(try rt.tradeListingPublish(draft: draftValue))
                } catch {
                    return .failure(error)
                }
            }.value

            switch result {
            case .success:
                isPosting = false
                onCreated?()
                dismiss()
            case .failure(let error):
                isPosting = false
                errorMessage = String(describing: error)
            }
        }
    }
}

private enum Field: Hashable {
    case farmPubkey
    case farmDTag
    case title
    case description
    case category
    case unitPrice
    case currency
    case binDisplayAmount
    case binLabel
    case inventory
    case locationPrimary
    case locationCity
    case locationRegion
    case locationCountry
}

private struct ListingDraftState {
    enum UnitOption: String, CaseIterable {
        case each
        case lb
        case oz
        case g
        case kg
        case l
        case ml

        var label: String {
            switch self {
            case .each: return "Each"
            case .lb: return "lb"
            case .oz: return "oz"
            case .g: return "g"
            case .kg: return "kg"
            case .l: return "L"
            case .ml: return "mL"
            }
        }
    }

    enum DeliveryMethod: String, CaseIterable {
        case pickup
        case localDelivery
        case shipping

        var label: String {
            switch self {
            case .pickup: return "Pickup"
            case .localDelivery: return "Local delivery"
            case .shipping: return "Shipping"
            }
        }

        var rawValueString: String {
            switch self {
            case .pickup: return "pickup"
            case .localDelivery: return "local_delivery"
            case .shipping: return "shipping"
            }
        }
    }

    var title: String = ""
    var description: String = ""
    var category: String = ""
    var farmPubkey: String = ""
    var farmDTag: String = ""
    var binDisplayUnit: UnitOption = .lb
    var binDisplayAmount: String = "1"
    var unitPrice: String = ""
    var currency: String = "USD"
    var binLabel: String = ""
    var inventory: String = ""
    var deliveryMethod: DeliveryMethod = .shipping
    var locationPrimary: String = ""
    var locationCity: String = ""
    var locationRegion: String = ""
    var locationCountry: String = ""

    var isValid: Bool {
        !farmPubkey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !farmDTag.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !category.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !binDisplayAmount.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !unitPrice.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !currency.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !inventory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !locationPrimary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func toTradeListingDraft() -> TradeListingDraft {
        let trimmedLabel = binLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        return TradeListingDraft(
            listingId: nil,
            farmPubkey: farmPubkey,
            farmDTag: farmDTag,
            title: title,
            description: description,
            category: category,
            binDisplayAmount: binDisplayAmount,
            binDisplayUnit: binDisplayUnit.rawValue,
            unitPrice: unitPrice,
            currency: currency,
            binLabel: trimmedLabel.isEmpty ? nil : trimmedLabel,
            binId: nil,
            inventory: inventory,
            deliveryMethod: deliveryMethod.rawValueString,
            locationPrimary: locationPrimary,
            locationCity: locationCity.isEmpty ? nil : locationCity,
            locationRegion: locationRegion.isEmpty ? nil : locationRegion,
            locationCountry: locationCountry.isEmpty ? nil : locationCountry
        )
    }

}
