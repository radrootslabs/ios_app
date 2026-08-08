import SwiftUI

enum RadrootsRootTab: String, CaseIterable, Sendable {
    case today
    case add

    static func resolve(_ rawValue: String?) -> Self {
        guard let rawValue, let tab = Self(rawValue: rawValue) else { return .today }
        return tab
    }

    static func resolve(url: URL) -> Self? {
        guard url.scheme?.lowercased() == "radroots",
              url.user == nil,
              url.password == nil,
              url.query == nil,
              url.fragment == nil
        else {
            return nil
        }
        let candidate = url.host ?? url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return Self(rawValue: candidate.lowercased())
    }
}

struct RadrootsRootShell: View {
    let snapshot: RadrootsRuntimeSnapshot
    @SceneStorage("radroots.selected_root_tab") private var storedSelection = RadrootsRootTab.today.rawValue

    var body: some View {
        TabView(selection: selection) {
            NavigationStack {
                RadrootsTodayLanding(snapshot: snapshot)
            }
            .tabItem { Label("Today", systemImage: "sun.max.fill") }
            .tag(RadrootsRootTab.today)
            .accessibilityIdentifier("radroots.tab.today")

            NavigationStack {
                RadrootsAddLanding()
            }
            .tabItem { Label("Add", systemImage: "plus.circle.fill") }
            .tag(RadrootsRootTab.add)
            .accessibilityIdentifier("radroots.tab.add")
        }
        .accessibilityIdentifier("radroots.root.tabs")
        .onOpenURL { url in
            guard let tab = RadrootsRootTab.resolve(url: url) else { return }
            storedSelection = tab.rawValue
        }
    }

    private var selection: Binding<RadrootsRootTab> {
        Binding(
            get: { RadrootsRootTab.resolve(storedSelection) },
            set: { storedSelection = $0.rawValue }
        )
    }
}

private struct RadrootsTodayLanding: View {
    let snapshot: RadrootsRuntimeSnapshot
    @State private var showsAccount = false
    @State private var showsSearch = false

    var body: some View {
        ContentUnavailableView {
            Label("Today", systemImage: "leaf.fill")
        } description: {
            Text("Your local food network is ready for its first refresh.")
        }
        .navigationTitle("Today")
        .toolbar {
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
        .sheet(isPresented: $showsAccount) {
            RadrootsAccountSheet(snapshot: snapshot)
        }
        .sheet(isPresented: $showsSearch) {
            RadrootsSearchSheet()
        }
        .accessibilityIdentifier("radroots.today.root")
    }
}

private struct RadrootsSearchSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ContentUnavailableView.search
                .navigationTitle("Search")
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
        }
        .accessibilityIdentifier("radroots.support.search.sheet")
    }
}

private struct RadrootsAccountSheet: View {
    let snapshot: RadrootsRuntimeSnapshot
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Me") {
                    LabeledContent("Public key", value: abbreviatedPublicKey)
                }
                Section("Connection") {
                    LabeledContent("Runtime", value: snapshot.crateVersion)
                    LabeledContent("Relay", value: snapshot.relay?.state ?? "Not configured")
                }
            }
            .navigationTitle("Account")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .accessibilityIdentifier("radroots.support.account.sheet")
    }

    private var abbreviatedPublicKey: String {
        let key = snapshot.identity.publicKeyHex
        guard key.count > 16 else { return key }
        return "\(key.prefix(8))…\(key.suffix(8))"
    }
}

private struct RadrootsAddLanding: View {
    var body: some View {
        ContentUnavailableView {
            Label("Add", systemImage: "plus.circle.fill")
        } description: {
            Text("Choose what to share with your local food network.")
        }
        .navigationTitle("Add")
        .accessibilityIdentifier("radroots.add.root")
    }
}
