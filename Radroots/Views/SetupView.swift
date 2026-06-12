import SwiftUI
import RadrootsKit

struct SetupView: View {
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var radroots: Radroots
    @EnvironmentObject private var keys: RadrootsKeys

    var onSuccess: (() -> Void)? = nil

    @State private var step: Step = .welcome
    @State private var isWorking = false
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            if step == .welcome {
                SetupWelcomeView {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        step = .keySetup
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .leading)))
            }

            if step == .keySetup {
                SetupKeyView(
                    isWorking: isWorking,
                    errorMessage: errorMessage,
                    onGenerate: generateKey,
                    onImport: importFromClipboard
                )
                .transition(.opacity.combined(with: .move(edge: .trailing)))
            }
        }
        .animation(.easeInOut(duration: 0.25), value: step)
        .toolbar(.hidden, for: .navigationBar)
        .accessibilityIdentifier("field_ios.setup")
    }

    private func generateKey() {
        guard let rt = radroots.runtime else {
            errorMessage = "Runtime not ready. Please relaunch."
            return
        }
        errorMessage = nil
        isWorking = true
        Task { @MainActor in
            do {
                try keys.generateAndPersist(runtime: rt)
                app.activateAfterKeyGeneration()
                onSuccess?()
            } catch {
                errorMessage = String(describing: error)
            }
            isWorking = false
        }
    }

    private func importFromClipboard() {
        guard let rt = radroots.runtime else {
            errorMessage = "Runtime not ready. Please relaunch."
            return
        }
        errorMessage = nil
        isWorking = true
        Task { @MainActor in
            do {
                let paste = UIPasteboard.general.string?.trimmingCharacters(in: .whitespacesAndNewlines)
                guard let hex = paste, !hex.isEmpty else {
                    throw NSError(domain: "Setup", code: -1, userInfo: [NSLocalizedDescriptionKey: "Clipboard is empty."])
                }
                try keys.importSecretHex(hex: hex, runtime: rt)
                app.activateAfterKeyGeneration()
                onSuccess?()
            } catch {
                errorMessage = String(describing: error)
            }
            isWorking = false
        }
    }
}

private enum Step {
    case welcome
    case keySetup
}

private struct SetupWelcomeView: View {
    let onContinue: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            Circle()
                .fill(Color(.systemGray5))
                .frame(width: 120, height: 120)
                .overlay(
                    Circle()
                        .strokeBorder(Color(.systemGray4), lineWidth: 1)
                )

            Text(Ls.setupGreetingHeader)
                .font(.title.weight(.semibold))
                .multilineTextAlignment(.center)

            Text(Ls.setupGreetingHeaderSub)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Spacer()

            Button {
                onContinue()
            } label: {
                Text("Continue")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .accessibilityIdentifier("field_ios.setup.continue")
        }
        .padding()
        .accessibilityIdentifier("field_ios.setup.welcome")
    }
}

private struct SetupKeyView: View {
    let isWorking: Bool
    let errorMessage: String?
    let onGenerate: () -> Void
    let onImport: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            VStack(spacing: 10) {
                Image(systemName: "key.fill")
                    .font(.system(size: 44, weight: .semibold))
                    .foregroundStyle(.secondary)

                Text("Set up your Nostr identity")
                    .font(.title2.weight(.semibold))
                    .multilineTextAlignment(.center)

                Text("Generate a new key or import an existing secret to get started.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            if let errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            if isWorking {
                ProgressView()
                    .controlSize(.large)
            }

            VStack(spacing: 12) {
                Button {
                    onGenerate()
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "sparkles")
                        Text("Generate New Key")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(isWorking)
                .accessibilityIdentifier("field_ios.setup.generate_key")

                Button {
                    onImport()
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "doc.on.clipboard")
                        Text("Import Secret Hex")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .disabled(isWorking)
                .accessibilityIdentifier("field_ios.setup.import_secret")
            }
            .padding(.top, 4)

            Spacer()

            Text("Your account is managed by the shared field runtime.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .accessibilityIdentifier("field_ios.setup.key")
    }
}
