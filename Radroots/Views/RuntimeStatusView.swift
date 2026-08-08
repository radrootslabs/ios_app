import SwiftUI

struct RuntimeStatusView: View {
    let phase: RadrootsAppModel.Phase
    let retry: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Spacer()
                Image(systemName: symbolName)
                    .font(.system(size: 48, weight: .medium))
                    .foregroundStyle(symbolColor)
                    .accessibilityHidden(true)
                Text(title)
                    .font(.title2.weight(.semibold))
                Text(detail)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                if case .failed = phase {
                    Button("Retry", action: retry)
                        .buttonStyle(.borderedProminent)
                        .accessibilityIdentifier("radroots.runtime.retry")
                }
                Spacer()
            }
            .padding(24)
            .navigationTitle("Radroots")
        }
        .accessibilityIdentifier("radroots.runtime.status")
    }

    private var symbolName: String {
        switch phase {
        case .starting: "leaf"
        case .identityRequired: "person.badge.key"
        case .running: "checkmark.circle"
        case .failed: "exclamationmark.triangle"
        case .stopped: "pause.circle"
        }
    }

    private var symbolColor: Color {
        switch phase {
        case .failed: .red
        case .running: .green
        default: .accentColor
        }
    }

    private var title: String {
        switch phase {
        case .starting: "Starting Radroots"
        case .identityRequired: "Set up your identity"
        case .running: "Radroots is ready"
        case .failed: "Radroots needs attention"
        case .stopped: "Radroots is paused"
        }
    }

    private var detail: String {
        switch phase {
        case .starting:
            "Preparing your local Radroots data."
        case .identityRequired:
            "Create or import an identity to connect your local food network."
        case let .running(snapshot):
            "Runtime \(snapshot.crateVersion) is connected to your local data."
        case let .failed(failure):
            failure.safeMessage
        case .stopped:
            "Your durable local work is safe."
        }
    }
}
