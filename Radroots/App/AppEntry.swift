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
            case .failed(let message):
                StartupFailureView(message: message) {
                    appState.retryStartup()
                }
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

private struct StartupFailureView: View {
    let message: String
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 56, weight: .semibold))
                .foregroundStyle(.red)
            Text("Startup failed")
                .font(.title2.weight(.semibold))
            Text(message)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .textSelection(.enabled)
            Spacer()
            Button {
                onRetry()
            } label: {
                Label("Retry", systemImage: "arrow.clockwise")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .accessibilityIdentifier("field_ios.bootstrap.retry")
        }
        .padding()
        .accessibilityIdentifier("field_ios.bootstrap.failed")
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
