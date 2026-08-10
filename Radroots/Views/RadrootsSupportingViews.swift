import RadrootsKit
import SwiftUI

struct RadrootsSearchSheet: View {
  let snapshot: RadrootsRuntimeSnapshot
  let context: RadrootsLocalNetwork?
  @ObservedObject var store: RadrootsSearchStore
  let revise: (RadrootsTodayCard) -> Void
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      Group {
        switch store.state {
        case .idle:
          ContentUnavailableView(
            "Search your local network",
            systemImage: "magnifyingglass",
            description: Text("Find current posts and adopted Nostr profiles.")
          )
        case .loading:
          ProgressView("Searching…")
        case .empty:
          ContentUnavailableView.search(text: store.query)
        case .failed(let message):
          ContentUnavailableView {
            Label("Search unavailable", systemImage: "exclamationmark.triangle")
          } description: {
            Text(message)
          } actions: {
            Button("Try again") { Task { await store.search() } }
          }
        case .loaded:
          resultList
        }
      }
      .navigationTitle("Search")
      .searchable(text: query, prompt: "Posts and profiles")
      .onSubmit(of: .search) { Task { await store.search() } }
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button("Done") { dismiss() }
        }
      }
    }
    .task { store.configure(context: context) }
    .accessibilityIdentifier("radroots.support.search.sheet")
  }

  private var resultList: some View {
    List(store.results) { result in
      switch (result.card, result.profile) {
      case (let card?, _):
        NavigationLink {
          RadrootsTodayDetailView(
            card: card,
            canRevise: card.authorPublicKey == snapshot.identity.publicKeyHex
              && card.localOperationID != nil,
            revise: revise
          )
        } label: {
          RadrootsTodayCardView(card: card)
        }
        .accessibilityIdentifier("radroots.search.card.\(result.id)")
      case (_, let profile?):
        NavigationLink {
          RadrootsProfileView(profile: profile)
        } label: {
          RadrootsProfileRow(profile: profile)
        }
        .accessibilityIdentifier("radroots.search.profile.\(result.id)")
      default:
        EmptyView()
      }
    }
    .listStyle(.plain)
    .accessibilityIdentifier("radroots.search.results")
  }

  private var query: Binding<String> {
    Binding(
      get: { store.query },
      set: { value in store.updateQuery(value) }
    )
  }
}

struct RadrootsMeSheet: View {
  let runtimeSnapshot: RadrootsRuntimeSnapshot
  let context: RadrootsLocalNetwork?
  @ObservedObject var store: RadrootsMeStore
  @ObservedObject var todayStore: RadrootsTodayStore
  @ObservedObject var addStore: RadrootsAddStore
  let revise: (RadrootsTodayCard) -> Void
  @Environment(\.dismiss) private var dismiss
  @State private var showsDrafts = false

  var body: some View {
    NavigationStack {
      Group {
        switch store.state {
        case .idle, .loading:
          ProgressView("Loading your profile…")
        case .failed(let message) where store.snapshot == nil:
          ContentUnavailableView {
            Label("Profile unavailable", systemImage: "person.crop.circle.badge.exclamationmark")
          } description: {
            Text(message)
          } actions: {
            Button("Try again") { Task { await store.reload() } }
          }
        default:
          content
        }
      }
      .navigationTitle("Me")
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button("Done") { dismiss() }
        }
      }
    }
    .sheet(isPresented: $showsDrafts) {
      RadrootsDraftsSheet(store: addStore)
    }
    .task {
      store.configure(context: context)
      await store.start()
    }
    .presentationDetents([.medium, .large])
    .accessibilityIdentifier("radroots.support.me.sheet")
  }

  private var content: some View {
    List {
      Section {
        if let profile = store.snapshot?.profile {
          NavigationLink {
            RadrootsProfileView(profile: profile)
          } label: {
            RadrootsProfileRow(profile: profile)
          }
        } else {
          RadrootsProfileRow(
            profile: RadrootsProfileSummary(
              authorPublicKey: store.snapshot?.publicKey ?? runtimeSnapshot.identity.publicKeyHex,
              name: nil,
              displayName: nil,
              about: nil,
              picture: nil,
              banner: nil,
              nip05: nil,
              website: nil,
              lightningAddress: nil
            )
          )
        }
      }

      Section("Local work") {
        Button {
          showsDrafts = true
        } label: {
          LabeledContent("Drafts & outbox", value: "\(addStore.drafts.count)")
        }
        .foregroundStyle(.primary)
        .accessibilityIdentifier("radroots.support.outbox")
      }

      Section("My posts") {
        if store.snapshot?.cards.isEmpty != false {
          Text("No current posts in this local network.")
            .foregroundStyle(.secondary)
        }
        ForEach(store.snapshot?.cards ?? []) { card in
          NavigationLink {
            RadrootsTodayDetailView(
              card: card,
              canRevise: card.localOperationID != nil,
              revise: revise
            )
          } label: {
            RadrootsTodayCardView(card: card)
          }
        }
      }

      Section {
        NavigationLink("Settings") {
          RadrootsSettingsView(
            snapshot: runtimeSnapshot,
            todayStore: todayStore,
            addStore: addStore
          )
        }
        .accessibilityIdentifier("radroots.support.settings")
      }
    }
    .refreshable { await store.reload() }
  }
}

struct RadrootsProfileRow: View {
  let profile: RadrootsProfileSummary

  var body: some View {
    HStack(spacing: 12) {
      RadrootsStableAvatarView(profile: profile, size: 48)
      VStack(alignment: .leading, spacing: 3) {
        Text(profile.preferredName)
          .font(.headline)
        if let nip05 = profile.nip05 {
          Text(nip05)
            .font(.caption)
            .foregroundStyle(.secondary)
        } else {
          Text(Self.abbreviate(profile.authorPublicKey))
            .font(.caption.monospaced())
            .foregroundStyle(.secondary)
        }
      }
    }
    .accessibilityElement(children: .combine)
    .accessibilityLabel("\(profile.preferredName), \(Self.abbreviate(profile.authorPublicKey))")
  }

  private static func abbreviate(_ key: String) -> String {
    guard key.count > 16 else { return key }
    return "\(key.prefix(8))…\(key.suffix(8))"
  }
}

struct RadrootsProfileView: View {
  let profile: RadrootsProfileSummary

  var body: some View {
    List {
      Section {
        VStack(spacing: 12) {
          RadrootsStableAvatarView(profile: profile, size: 88)
          Text(profile.preferredName)
            .font(.title2.weight(.semibold))
          Text(abbreviatedPublicKey)
            .font(.caption.monospaced())
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
      }
      if let about = profile.about, !about.isEmpty {
        Section("About") { Text(about) }
      }
      Section("Nostr profile") {
        if let nip05 = profile.nip05 {
          LabeledContent("NIP-05", value: nip05)
        }
        if let website = safeHTTPS(profile.website) {
          Link(destination: website) {
            LabeledContent("Website", value: website.host ?? website.absoluteString)
          }
        }
        if let address = profile.lightningAddress {
          LabeledContent("Lightning", value: address)
        }
      }
    }
    .navigationTitle("Profile")
    .navigationBarTitleDisplayMode(.inline)
    .accessibilityIdentifier("radroots.profile.\(profile.authorPublicKey)")
  }

  private var abbreviatedPublicKey: String {
    guard profile.authorPublicKey.count > 16 else { return profile.authorPublicKey }
    return "\(profile.authorPublicKey.prefix(8))…\(profile.authorPublicKey.suffix(8))"
  }

  private func safeHTTPS(_ value: String?) -> URL? {
    guard let value,
      let url = URL(string: value),
      url.scheme?.lowercased() == "https",
      url.host != nil,
      url.user == nil,
      url.password == nil
    else {
      return nil
    }
    return url
  }
}

struct RadrootsStableAvatarView: View {
  let profile: RadrootsProfileSummary
  let size: CGFloat

  var body: some View {
    let identity = RadrootsStableVisualIdentity(publicKeyHex: profile.authorPublicKey)
    ZStack {
      Circle().fill(Self.palette[identity.paletteIndex])
      Text(String(profile.preferredName.prefix(1)).uppercased())
        .font(.system(size: size * 0.4, weight: .semibold, design: .rounded))
        .foregroundStyle(.white)
    }
    .frame(width: size, height: size)
    .accessibilityHidden(true)
  }

  private static let palette: [Color] = [
    .indigo, .mint, .orange, .purple, .teal, .pink,
    .blue, .green, .red, .cyan, .brown, .yellow,
  ]
}

struct RadrootsSettingsView: View {
  let snapshot: RadrootsRuntimeSnapshot
  @ObservedObject var todayStore: RadrootsTodayStore
  @ObservedObject var addStore: RadrootsAddStore
  @EnvironmentObject private var diagnosticsStore: RadrootsDiagnosticsStore

  var body: some View {
    List {
      Section("Identity") {
        LabeledContent(
          "Local signer",
          value: snapshot.identity.hostSignerConfigured ? "Ready" : "Needs attention")
        LabeledContent("Public key", value: abbreviatedPublicKey)
          .accessibilityIdentifier("radroots.settings.identity.public_key")
          .accessibilityValue(snapshot.identity.publicKeyHex)
      }
      Section("Nostr relays") {
        if snapshot.relay?.relays.isEmpty != false {
          Text("No relay is configured for this profile.")
            .foregroundStyle(.secondary)
        }
        ForEach(snapshot.relay?.relays ?? [], id: \.url) { relay in
          VStack(alignment: .leading, spacing: 4) {
            Text(relay.url).font(.caption.monospaced())
            Text("\(relay.access.label) · read \(relay.readState) · write \(relay.writeState)")
              .font(.caption2)
              .foregroundStyle(.secondary)
          }
        }
        Button("Retry local network") { Task { await todayStore.reload() } }
          .accessibilityIdentifier("radroots.settings.retry.network")
      }
      Section("Blossom photos") {
        if let configuration = addStore.blossomConfiguration {
          LabeledContent("Origin", value: configuration.primaryOrigin)
            .accessibilityIdentifier("radroots.settings.blossom.origin")
          LabeledContent("Configuration", value: abbreviated(configuration.configFingerprint))
            .accessibilityIdentifier("radroots.settings.blossom.fingerprint")
        } else {
          Text("No photo service is configured for this network profile.")
            .foregroundStyle(.secondary)
        }
        if let evidence = addStore.blossomEvidence {
          LabeledContent("Service state", value: display(evidence.state))
            .accessibilityIdentifier("radroots.settings.blossom.state")
          LabeledContent("Connection", value: display(evidence.transportSecurity))
          if evidence.lastSuccessfulState != "none" {
            LabeledContent("Last success", value: display(evidence.lastSuccessfulState))
          }
          if let status = evidence.httpStatus {
            LabeledContent("HTTP status", value: String(status))
              .accessibilityIdentifier("radroots.settings.blossom.http_status")
          }
          if let errorCode = evidence.errorCode {
            LabeledContent("Last error", value: display(errorCode))
              .accessibilityIdentifier("radroots.settings.blossom.error_code")
          }
          if let serverErrorCode = evidence.serverErrorCode {
            LabeledContent("Server error", value: display(serverErrorCode))
              .accessibilityIdentifier("radroots.settings.blossom.server_error_code")
          }
          if evidence.attempts > 0 {
            LabeledContent("Attempts", value: String(evidence.attempts))
          }
          if evidence.possibleOrphan {
            Text("The server may contain an upload whose verification did not complete.")
              .foregroundStyle(.orange)
          }
        }
        LabeledContent(
          "Photo library", value: addStore.mediaSupport.library ? "Ready" : "Unavailable")
        LabeledContent("Camera", value: addStore.mediaSupport.camera ? "Ready" : "Unavailable")
        Button {
          Task { await addStore.checkPhotoService() }
        } label: {
          if addStore.isCheckingBlossom {
            ProgressView()
          } else {
            Text("Check photo service")
          }
        }
        .disabled(addStore.isCheckingBlossom || addStore.blossomConfiguration == nil)
        .accessibilityIdentifier("radroots.settings.retry.blossom")
      }
      Section("Runtime") {
        LabeledContent("Crate", value: snapshot.crateName)
        LabeledContent("Version", value: snapshot.crateVersion)
        LabeledContent("State", value: snapshot.isClosed ? "Closed" : "Running")
      }
      Section {
        if let message = diagnosticsStore.message {
          Text(message)
            .foregroundStyle(.secondary)
        }
        Button("Prepare diagnostics export") {
          Task { await diagnosticsStore.prepare(snapshot: snapshot) }
        }
        .disabled(diagnosticsStore.isPreparing)
        .accessibilityIdentifier("radroots.settings.diagnostics")
      } header: {
        Text("Privacy-safe diagnostics")
      } footer: {
        Text(
          "Exports contain bounded lifecycle codes and runtime status only. Posts, keys, credentials, endpoint URLs, and local paths are excluded."
        )
      }
    }
    .navigationTitle("Settings")
    .radrootsDocumentExporter(preparedExport: $diagnosticsStore.preparedExport) { result in
      diagnosticsStore.completeExport(result)
    }
    .accessibilityIdentifier("radroots.support.settings.view")
  }

  private var abbreviatedPublicKey: String {
    let key = snapshot.identity.publicKeyHex
    guard key.count > 16 else { return key }
    return "\(key.prefix(8))…\(key.suffix(8))"
  }

  private func abbreviated(_ value: String) -> String {
    guard value.count > 16 else { return value }
    return "\(value.prefix(8))…\(value.suffix(8))"
  }

  private func display(_ value: String) -> String {
    value.replacingOccurrences(of: "_", with: " ")
  }
}
