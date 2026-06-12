import SwiftUI

private enum HomeTab: String, Hashable {
    case today
    case capture
    case activity
    case settings
}

struct HomeView: View {
    @AppStorage("field_ios.selected_tab") private var selection = HomeTab.today.rawValue

    var body: some View {
        TabView(selection: $selection) {
            NavigationStack {
                TodayView()
            }
            .tabItem { Label("Today", systemImage: "sun.max.fill") }
            .tag(HomeTab.today.rawValue)
            .accessibilityIdentifier("field_ios.today.tab")

            NavigationStack {
                CaptureView()
            }
            .tabItem { Label("Capture", systemImage: "camera.viewfinder") }
            .tag(HomeTab.capture.rawValue)
            .accessibilityIdentifier("field_ios.capture.tab")

            NavigationStack {
                ActivityView()
            }
            .tabItem { Label("Activity", systemImage: "list.bullet.clipboard.fill") }
            .tag(HomeTab.activity.rawValue)
            .accessibilityIdentifier("field_ios.activity.tab")

            NavigationStack {
                SettingsView()
            }
            .tabItem { Label("Settings", systemImage: "gearshape.fill") }
            .tag(HomeTab.settings.rawValue)
            .accessibilityIdentifier("field_ios.settings.tab")
        }
        .accessibilityIdentifier("field_ios.home.tabs")
    }
}

private struct TodayView: View {
    @EnvironmentObject private var app: AppState

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Today")
                        .font(.largeTitle.weight(.bold))
                    Text(app.identityDisplayName)
                        .font(.title3.weight(.semibold))
                    HStack(spacing: 10) {
                        Label(syncLabel, systemImage: syncImage)
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        RelayPill(count: app.relayConnectedCount)
                    }
                }
                .padding(.vertical, 4)
            }

            Section("Next Actions") {
                FieldActionRow(title: "Photo Evidence", subtitle: "Document a crop, delivery, or field condition.", systemImage: "camera.fill")
                FieldActionRow(title: "Location Check-in", subtitle: "Record where field work is happening.", systemImage: "location.fill")
                FieldActionRow(title: "Status Log", subtitle: "Capture a short operational update.", systemImage: "text.badge.checkmark")
                FieldActionRow(title: "Compliance Note", subtitle: "Reserve audit-ready notes for the current workflow.", systemImage: "checkmark.seal.fill")
            }

            Section("Diagnostics") {
                RelayMetricRow(label: "Connected", systemImage: "dot.radiowaves.left.and.right", value: app.relayConnectedCount)
                RelayMetricRow(label: "Connecting", systemImage: "antenna.radiowaves.left.and.right", value: app.relayConnectingCount)
                if let last = app.relayLastError {
                    Text(last)
                        .foregroundStyle(.red)
                        .font(.footnote)
                }
                Text(app.infoJSONString)
                    .font(.footnote.monospaced())
                    .textSelection(.enabled)
                    .lineLimit(8)
            }
        }
        .listStyle(.insetGrouped)
        .inlineNavigationTitle("Today")
        .accessibilityIdentifier("field_ios.today")
    }

    private var syncLabel: String {
        app.relayConnectedCount > 0 ? "Sync online" : "Waiting for relay"
    }

    private var syncImage: String {
        app.relayConnectedCount > 0 ? "checkmark.icloud.fill" : "icloud.slash.fill"
    }
}

private struct CaptureView: View {
    var body: some View {
        List {
            Section("Capture") {
                FieldActionRow(title: "Photo Evidence", subtitle: "Attach visual proof to field work.", systemImage: "camera.fill")
                FieldActionRow(title: "Location Check-in", subtitle: "Pair a note with the current site.", systemImage: "location.fill")
                FieldActionRow(title: "Status Log", subtitle: "Record observations from the field.", systemImage: "square.and.pencil")
                FieldActionRow(title: "Compliance Note", subtitle: "Prepare traceability notes for review.", systemImage: "checkmark.seal.fill")
            }
        }
        .listStyle(.insetGrouped)
        .inlineNavigationTitle("Capture")
        .accessibilityIdentifier("field_ios.capture")
    }
}

private struct ActivityView: View {
    @EnvironmentObject private var app: AppState

    var body: some View {
        List {
            Section("Recent Activity") {
                ActivityRow(title: "Identity ready", detail: app.npub.map(shortNpub) ?? "Local key selected", systemImage: "person.crop.circle.badge.checkmark")
                ActivityRow(title: "Relay posture", detail: "\(app.relayConnectedCount) connected, \(app.relayConnectingCount) connecting", systemImage: "dot.radiowaves.left.and.right")
                ActivityRow(title: "Draft queue", detail: "No local drafts", systemImage: "tray")
            }
        }
        .listStyle(.insetGrouped)
        .inlineNavigationTitle("Activity")
        .accessibilityIdentifier("field_ios.activity")
    }

    private func shortNpub(_ value: String) -> String {
        guard value.count > 18 else { return value }
        return "\(value.prefix(12))...\(value.suffix(6))"
    }
}

private struct FieldActionRow: View {
    let title: String
    let subtitle: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.green)
                .frame(width: 34, height: 34)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

private struct ActivityRow: View {
    let title: String
    let detail: String
    let systemImage: String

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: systemImage)
                .foregroundStyle(.green)
        }
        .padding(.vertical, 4)
    }
}

private struct RelayPill: View {
    let count: UInt32

    var body: some View {
        Text("\(count) connected")
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .foregroundStyle(count > 0 ? .green : .secondary)
            .background(.thinMaterial, in: Capsule())
    }
}

private struct RelayMetricRow: View {
    let label: String
    let systemImage: String
    let value: UInt32

    var body: some View {
        HStack {
            Label(label, systemImage: systemImage)
            Spacer()
            Text("\(value)")
                .foregroundStyle(.secondary)
        }
    }
}
