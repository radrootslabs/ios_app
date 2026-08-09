import SwiftUI

struct RuntimeStatusView: View {
    let phase: RadrootsAppModel.Phase
    let retry: () -> Void
    let createIdentity: () -> Void
    let unlockIdentity: () -> Void
    let recoverIdentity: () -> Void
    let applyConfigurationReconfiguration: () -> Void

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
                if case let .failed(failure) = phase {
                    Text("Error code \(failure.code)")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("radroots.runtime.failure_code")
                }
                if case .identityRequired = phase {
                    Button("Create identity", action: createIdentity)
                        .buttonStyle(.borderedProminent)
                        .accessibilityIdentifier("radroots.identity.create")
                } else if case .identityLocked = phase {
                    Button("Unlock identity", action: unlockIdentity)
                        .buttonStyle(.borderedProminent)
                        .accessibilityIdentifier("radroots.identity.unlock")
                } else if case .recoveryRequired = phase {
                    Button("Recover identity", action: recoverIdentity)
                        .buttonStyle(.borderedProminent)
                        .accessibilityIdentifier("radroots.identity.recover")
                } else if case .configurationReconfigurationRequired = phase {
                    Button("Apply network configuration", action: applyConfigurationReconfiguration)
                        .buttonStyle(.borderedProminent)
                        .accessibilityIdentifier("radroots.configuration.reconfigure")
                } else if case .failed = phase {
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
        case .identityLocked: "lock"
        case .protectedDataUnavailable: "lock.iphone"
        case .recoveryRequired: "wrench.and.screwdriver"
        case .corruptIdentity: "exclamationmark.shield"
        case .configurationReconfigurationRequired: "arrow.triangle.2.circlepath"
        case .running: "checkmark.circle"
        case .failed: "exclamationmark.triangle"
        case .stopped: "pause.circle"
        }
    }

    private var symbolColor: Color {
        switch phase {
        case .failed, .corruptIdentity: .red
        case .configurationReconfigurationRequired: .orange
        case .running: .green
        default: .accentColor
        }
    }

    private var title: String {
        switch phase {
        case .starting: "Starting Radroots"
        case .identityRequired: "Set up your identity"
        case .identityLocked: "Unlock your identity"
        case .protectedDataUnavailable: "Unlock this device"
        case .recoveryRequired: "Recover your identity"
        case .corruptIdentity: "Identity data needs repair"
        case .configurationReconfigurationRequired: "Network configuration changed"
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
        case .identityLocked:
            "Your local Nostr secret remains protected until you explicitly unlock it."
        case .protectedDataUnavailable:
            "Protected local data is unavailable while this device is locked."
        case let .recoveryRequired(identity):
            identity.recoveryCode ?? "A previous identity operation needs recovery."
        case let .corruptIdentity(identity):
            identity.recoveryCode ?? "Stored identity state is corrupt; it was not treated as absent."
        case let .configurationReconfigurationRequired(requirement):
            if let fingerprint = requirement.previousBlossomConfigFingerprint {
                "Review and apply the new network configuration. Existing uploads remain bound to configuration \(fingerprint.prefix(12))…."
            } else {
                "Review and apply the new network configuration. Existing local identity and drafts are preserved."
            }
        case let .running(snapshot):
            "Runtime \(snapshot.crateVersion) is connected to your local data."
        case let .failed(failure):
            failure.safeMessage
        case .stopped:
            "Your durable local work is safe."
        }
    }

}
