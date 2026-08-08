import SwiftUI

struct RadrootsProvider<Content: View>: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var appModel: RadrootsAppModel
    private let content: () -> Content

    init(
        appModel: @autoclosure @escaping () -> RadrootsAppModel = RadrootsAppModel(),
        @ViewBuilder content: @escaping () -> Content
    ) {
        _appModel = StateObject(wrappedValue: appModel())
        self.content = content
    }

    var body: some View {
        content()
            .environmentObject(appModel)
            .task { await appModel.start() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    Task { await appModel.start() }
                } else if phase == .background {
                    Task { await appModel.stop() }
                }
            }
    }
}
