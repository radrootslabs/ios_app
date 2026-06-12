import SwiftUI

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
        .accessibilityIdentifier("field_ios.app_entry")
    }
}

private struct SplashView: View {
    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()
            ProgressView().controlSize(.large)
        }
        .accessibilityIdentifier("field_ios.bootstrap")
    }
}
