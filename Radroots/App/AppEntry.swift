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
        .overlay(alignment: .topLeading) {
            if let probeValue = appState.fileAccessProbeValue {
                Color.clear
                    .frame(width: 1, height: 1)
                    .accessibilityElement()
                    .accessibilityIdentifier("field_ios.file_access.probe")
                    .accessibilityValue(probeValue)
            }
        }
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
    private let splashGlyphSize: CGFloat = 160

    var body: some View {
        ZStack {
            Color("RadrootsSplashBackground")
                .ignoresSafeArea()

            Color.clear
                .accessibilityElement()
                .accessibilityLabel("Startup")
                .accessibilityIdentifier("field_ios.bootstrap")

            GeometryReader { proxy in
                Image("RadrootsSplashLogomark")
                    .resizable()
                    .scaledToFit()
                    .frame(width: splashGlyphSize, height: splashGlyphSize)
                    .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
                    .accessibilityLabel("Radroots")
                    .accessibilityIdentifier("field_ios.splash.logo")
            }
            .ignoresSafeArea()
        }
        .accessibilityElement(children: .contain)
    }
}
