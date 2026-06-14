import RadrootsKit
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
                LocationCheckInRow()
                FieldActionRow(title: "Status Log", subtitle: "Capture a short operational update.", systemImage: "text.badge.checkmark")
                FieldActionRow(title: "Compliance Note", subtitle: "Reserve audit-ready notes for the current workflow.", systemImage: "checkmark.seal.fill")
            }

            Section("Relay") {
                RelayMetricRow(label: "Connected", systemImage: "dot.radiowaves.left.and.right", value: app.relayConnectedCount)
                RelayMetricRow(label: "Connecting", systemImage: "antenna.radiowaves.left.and.right", value: app.relayConnectingCount)
                if let last = app.relayLastError {
                    Text(last)
                        .foregroundStyle(.red)
                        .font(.footnote)
                }
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
    @EnvironmentObject private var app: AppState

    var body: some View {
        List {
            Section("Capture") {
                FieldActionRow(title: "Photo Evidence", subtitle: "Attach visual proof to field work.", systemImage: "camera.fill")
                LocationCheckInRow()
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

private struct LocationCheckInRow: View {
    @EnvironmentObject private var app: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: systemImage)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(systemColor)
                    .frame(width: 34, height: 34)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Location Check-in")
                        .font(.headline)
                    Text(statusText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("field_ios.location_check_in.status")
                    if let detailText {
                        Text(detailText)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("field_ios.location_check_in.detail")
                    }
                }
                Spacer()
                if isChecking {
                    ProgressView()
                        .accessibilityIdentifier("field_ios.location_check_in.progress")
                }
            }

            Button {
                Task {
                    await app.performLocationCheckIn()
                }
            } label: {
                Label(actionTitle, systemImage: "location.fill")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isChecking)
            .accessibilityIdentifier("field_ios.location_check_in.action")
        }
        .padding(.vertical, 4)
        .accessibilityIdentifier("field_ios.location_check_in.card")
        .task {
            await app.refreshLocationCheckInStatus()
        }
    }

    private var isChecking: Bool {
        if case .checking = app.locationCheckInState {
            return true
        }
        return false
    }

    private var systemImage: String {
        switch app.locationCheckInState {
        case .checkedIn:
            "location.circle.fill"
        case .failed:
            "location.slash.fill"
        case .checking:
            "location.fill"
        case .idle(let availability):
            availability.canRequestCurrentLocation ? "location.circle.fill" : "location.fill"
        }
    }

    private var systemColor: Color {
        switch app.locationCheckInState {
        case .checkedIn:
            .green
        case .failed:
            .red
        case .checking:
            .green
        case .idle(let availability):
            availability.canRequestCurrentLocation ? .green : .secondary
        }
    }

    private var actionTitle: String {
        isChecking ? "Checking In" : "Check In"
    }

    private var statusText: String {
        switch app.locationCheckInState {
        case .idle(let availability):
            statusText(for: availability)
        case .checking:
            "Checking current location..."
        case .checkedIn(let reading):
            "Checked in at \(reading.coordinateSummary)"
        case .failed(_, let message):
            "Check-in unavailable: \(message)"
        }
    }

    private var detailText: String? {
        switch app.locationCheckInState {
        case .checkedIn(let reading):
            reading.accuracySummary
        case .idle(let availability):
            availability.authorization == .notDetermined ? "Permission will be requested when you check in." : nil
        case .checking, .failed:
            nil
        }
    }

    private func statusText(for availability: RadrootsLocationServicesAvailability) -> String {
        guard availability.locationServicesEnabled else {
            return "Location Services are disabled."
        }
        switch availability.authorization {
        case .notDetermined:
            return "Ready to request location permission."
        case .authorizedWhenInUse, .authorizedAlways:
            return "Ready to record the current site."
        case .denied:
            return "Location permission is denied."
        case .restricted:
            return "Location permission is restricted."
        case .unavailable:
            return "Location Services are unavailable."
        case .unsupported:
            return "Location Services are unsupported."
        }
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
