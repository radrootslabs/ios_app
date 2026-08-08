import SwiftUI

struct AppEntry: View {
    @EnvironmentObject private var appModel: RadrootsAppModel

    var body: some View {
        RuntimeStatusView(
            phase: appModel.phase,
            retry: { Task { await appModel.retry() } },
            createIdentity: { Task { await appModel.createIdentity() } },
            unlockIdentity: { Task { await appModel.unlockIdentity() } },
            recoverIdentity: { Task { await appModel.recoverIdentity() } }
        )
        .accessibilityIdentifier("radroots.app_entry")
    }
}
