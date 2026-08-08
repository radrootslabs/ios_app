import SwiftUI

public enum RadrootsAppRelease: Sendable {
    public static let version = "0.1.0-alpha"
}

public struct RadrootsAppView: View {
    public init() {}

    public var body: some View {
        RadrootsProvider {
            AppEntry()
        }
    }
}

struct AppEntry: View {
    @EnvironmentObject private var appModel: RadrootsAppModel

    var body: some View {
        Group {
            if case let .running(snapshot) = appModel.phase {
                RadrootsRootShell(
                    snapshot: snapshot,
                    todayStore: appModel.todayStore,
                    addStore: appModel.addStore,
                    searchStore: appModel.searchStore,
                    meStore: appModel.meStore
                )
            } else {
                RuntimeStatusView(
                    phase: appModel.phase,
                    retry: { Task { await appModel.retry() } },
                    createIdentity: { Task { await appModel.createIdentity() } },
                    unlockIdentity: { Task { await appModel.unlockIdentity() } },
                    recoverIdentity: { Task { await appModel.recoverIdentity() } },
                    applyConfigurationReconfiguration: {
                        Task { await appModel.applyConfigurationReconfiguration() }
                    }
                )
            }
        }
        .accessibilityIdentifier("radroots.app_entry")
    }
}
