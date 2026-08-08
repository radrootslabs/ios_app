import SwiftUI

struct RadrootsTodayView: View {
    let snapshot: RadrootsRuntimeSnapshot
    @ObservedObject var store: RadrootsTodayStore
    @State private var showsAccount = false
    @State private var showsContextPicker = false
    @State private var showsSearch = false

    var body: some View {
        Group {
            switch store.state {
            case .idle where store.cards.isEmpty,
                 .loading where store.cards.isEmpty:
                ProgressView("Loading Today…")
                    .accessibilityIdentifier("radroots.today.loading")
            case .empty:
                ContentUnavailableView {
                    Label("Nothing here yet", systemImage: "leaf")
                } description: {
                    Text("Pull to refresh or add the first update to this local network.")
                } actions: {
                    Button("Refresh") { Task { await store.reload() } }
                }
                .accessibilityIdentifier("radroots.today.empty")
            case let .failed(message) where store.cards.isEmpty:
                unavailableView(
                    title: "Today is unavailable",
                    message: message,
                    systemImage: "exclamationmark.triangle"
                )
                .accessibilityIdentifier("radroots.today.error")
            case let .offline(message) where store.cards.isEmpty:
                unavailableView(
                    title: "You’re offline",
                    message: message,
                    systemImage: "wifi.slash"
                )
                .accessibilityIdentifier("radroots.today.offline")
            default:
                feed
            }
        }
        .navigationTitle("Today")
        .toolbar { toolbarContent }
        .sheet(isPresented: $showsContextPicker) {
            RadrootsContextPicker(store: store)
        }
        .sheet(isPresented: $showsAccount) {
            RadrootsAccountSheet(snapshot: snapshot)
        }
        .sheet(isPresented: $showsSearch) {
            RadrootsSearchSheet()
        }
        .task { await store.start() }
        .accessibilityIdentifier("radroots.today.root")
    }

    private var feed: some View {
        List {
            if case let .offline(message) = store.state {
                statusBanner(message: message, systemImage: "wifi.slash")
            } else if case let .failed(message) = store.state {
                statusBanner(message: message, systemImage: "exclamationmark.triangle")
            }

            ForEach(store.cards) { card in
                NavigationLink(value: card) {
                    RadrootsTodayCardView(card: card)
                }
                .accessibilityIdentifier("radroots.today.card.\(card.id)")
                .onAppear {
                    guard card.id == store.cards.last?.id, store.canLoadNextPage else { return }
                    Task { await store.loadNextPage() }
                }
            }

            if store.isLoadingNextPage {
                HStack {
                    Spacer()
                    ProgressView("Loading more…")
                    Spacer()
                }
                .accessibilityIdentifier("radroots.today.loading_more")
            }
        }
        .listStyle(.plain)
        .refreshable { await store.reload() }
        .navigationDestination(for: RadrootsTodayCard.self) { card in
            RadrootsTodayDetailView(card: card)
        }
        .accessibilityIdentifier("radroots.today.feed")
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button {
                showsContextPicker = true
            } label: {
                Label(store.selectedContext?.label ?? "Local network", systemImage: "location.circle")
            }
            .accessibilityLabel("Choose local network")
            .accessibilityValue(store.selectedContext?.label ?? "None")
            .accessibilityIdentifier("radroots.support.context")
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                showsSearch = true
            } label: {
                Label("Search", systemImage: "magnifyingglass")
            }
            .accessibilityIdentifier("radroots.support.search")
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                showsAccount = true
            } label: {
                Label("Account", systemImage: "person.crop.circle")
            }
            .accessibilityIdentifier("radroots.support.account")
        }
    }

    private func unavailableView(
        title: String,
        message: String,
        systemImage: String
    ) -> some View {
        ContentUnavailableView {
            Label(title, systemImage: systemImage)
        } description: {
            Text(message)
        } actions: {
            Button("Try again") { Task { await store.reload() } }
        }
    }

    private func statusBanner(message: String, systemImage: String) -> some View {
        Label(message, systemImage: systemImage)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .accessibilityIdentifier("radroots.today.status")
    }
}

private struct RadrootsContextPicker: View {
    @ObservedObject var store: RadrootsTodayStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(store.contexts) { context in
                Button {
                    store.selectContext(id: context.id)
                    dismiss()
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(context.label)
                                .foregroundStyle(.primary)
                            if let locality = context.locality {
                                Text(locality)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        if context.id == store.selectedContextID {
                            Image(systemName: "checkmark")
                                .accessibilityHidden(true)
                        }
                    }
                }
                .accessibilityLabel(context.label)
                .accessibilityValue(context.id == store.selectedContextID ? "Selected" : "")
                .accessibilityIdentifier("radroots.context.\(context.id)")
            }
            .navigationTitle("Local network")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .accessibilityIdentifier("radroots.context.picker")
    }
}

private struct RadrootsTodayCardView: View {
    let card: RadrootsTodayCard

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(card.authorName)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(card.type.label)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.tint.opacity(0.12), in: Capsule())
            }

            if let title = card.title {
                Text(title)
                    .font(.headline)
            }
            if !card.content.isEmpty {
                Text(card.content)
                    .font(card.type == .ask ? .headline : .body)
            }

            if card.type == .event {
                eventMetadata
            }
            if card.type == .foodAvailability {
                foodMetadata
            }

            ForEach(card.media) { media in
                RadrootsTrustedMediaView(media: media)
            }

            HStack(spacing: 12) {
                Text(Date(timeIntervalSince1970: TimeInterval(card.authoredAtUnixSeconds)), style: .relative)
                if card.lifecycle != .active {
                    Label(card.lifecycle.rawValue.capitalized, systemImage: "clock")
                }
                if let operationState = card.localOperationState {
                    Label(operationState.replacingOccurrences(of: "_", with: " ").capitalized, systemImage: "arrow.triangle.2.circlepath")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(card.accessibilitySummary)
    }

    private var eventMetadata: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let start = card.eventStartUnixSeconds {
                Label(
                    Date(timeIntervalSince1970: TimeInterval(start)).formatted(date: .abbreviated, time: .shortened),
                    systemImage: "calendar"
                )
            }
            if let location = card.location {
                Label(location, systemImage: "mappin.and.ellipse")
            }
        }
        .font(.subheadline)
    }

    private var foodMetadata: some View {
        HStack(spacing: 12) {
            if let price = card.priceSummary {
                Label(price, systemImage: "tag")
            }
            if let quantity = card.quantity, let unit = card.priceUnit {
                Label("\(quantity) \(unit) available", systemImage: "basket")
            }
            if let location = card.location {
                Label(location, systemImage: "mappin.and.ellipse")
            }
        }
        .font(.subheadline)
    }
}

private struct RadrootsTrustedMediaView: View {
    let media: RadrootsMediaReference

    var body: some View {
        Group {
            if let url = media.trustedURL {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case let .success(image):
                        image.resizable().scaledToFill()
                    case .failure:
                        mediaState("Media could not be loaded", systemImage: "photo.badge.exclamationmark")
                    case .empty:
                        ProgressView()
                    @unknown default:
                        mediaState("Media unavailable", systemImage: "photo")
                    }
                }
            } else {
                switch media.verification {
                case .pending:
                    mediaState("Verifying media", systemImage: "hourglass")
                case .failed:
                    mediaState("Media failed verification", systemImage: "shield.slash")
                case .unavailable:
                    mediaState("Media not verified", systemImage: "shield.lefthalf.filled")
                case .verified:
                    mediaState("Media URL is not trusted", systemImage: "lock.trianglebadge.exclamationmark")
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 120, maxHeight: 260)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .accessibilityLabel(media.alt ?? media.verification.rawValue.capitalized)
    }

    private func mediaState(_ message: String, systemImage: String) -> some View {
        ContentUnavailableView(message, systemImage: systemImage)
            .font(.caption)
    }
}

private struct RadrootsTodayDetailView: View {
    let card: RadrootsTodayCard

    var body: some View {
        List {
            Section {
                RadrootsTodayCardView(card: card)
            }
            if !card.thread.isEmpty {
                Section("Conversation") {
                    ForEach(card.thread) { entry in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(entry.authorProfile?.preferredName ?? entry.authorPublicKey)
                                .font(.subheadline.weight(.semibold))
                            Text(entry.content)
                            Text(entry.type.rawValue.capitalized)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
        .navigationTitle(card.type.label)
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("radroots.today.detail.\(card.id)")
    }
}
