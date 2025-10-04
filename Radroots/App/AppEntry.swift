import SwiftUI
import RadrootsKit

public struct AppEntry<Main: View>: View {
    @EnvironmentObject private var appState: AppState
    private let main: () -> Main

    public init(@ViewBuilder main: @escaping () -> Main) {
        self.main = main
    }

    public var body: some View {
        Group {
            switch appState.bootstrapPhase {
            case .idle, .starting:
                SplashView()
            case .ready:
                if appState.canShowAppContent {
                    main()
                } else {
                    NavigationStack {
                        SetupView()
                    }
                }
            }
        }
    }
}

private struct SplashView: View {
    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()
            ProgressView().controlSize(.large)
        }
    }
}
