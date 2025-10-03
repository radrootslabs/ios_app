import SwiftUI
import RadrootsKit

struct ProfileView: View {
@EnvironmentObject private var appState: AppState
@EnvironmentObject private var radroots: Radroots

@State private var name: String = ""
@State private var displayName: String = ""
@State private var nip05: String = ""
@State private var about: String = ""

var body: some View {
    Form {
        Section("Account") {
            LabeledContent("npub", value: appState.npub ?? "—")
        }
        Section("Profile") {
            LabeledContent("name", value: name.isEmpty ? "—" : name)
            LabeledContent("display_name", value: displayName.isEmpty ? "—" : displayName)
            LabeledContent("nip05", value: nip05.isEmpty ? "—" : nip05)
            VStack(alignment: .leading, spacing: 8) {
                Text("about").font(.footnote).foregroundStyle(.secondary)
                Text(about.isEmpty ? "—" : about)
            }
        }
    }
    .navigationTitle("Profile")
    .task { await load() }
    .refreshable { await load() }
}

private func apply(profile: NostrProfile?) {
    name = profile?.name ?? ""
    displayName = profile?.displayName ?? ""
    nip05 = profile?.nip05 ?? ""
    about = profile?.about ?? ""
}

private func load() async {
    guard let rt = radroots.runtime, appState.hasKey else {
        apply(profile: nil)
        return
    }
    let profile = rt.nostrProfileForSelf()
    apply(profile: profile)
}
}
