import SwiftUI

struct AppEntry: View {
    @EnvironmentObject private var appModel: RadrootsAppModel

    var body: some View {
        RuntimeStatusView(phase: appModel.phase) {
            Task { await appModel.retry() }
        }
        .accessibilityIdentifier("radroots.app_entry")
    }
}
