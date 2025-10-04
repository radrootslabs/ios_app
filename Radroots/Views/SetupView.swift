import SwiftUI
import RadrootsKit

struct SetupView: View {
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var radroots: Radroots
    @EnvironmentObject private var keys: RadrootsKeys

    var onSuccess: (() -> Void)? = nil

    @State private var isWorking = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "key.fill")
                .font(.system(size: 60, weight: .bold))
            Text("Set up your Nostr Identity")
                .font(.title2.weight(.semibold))

            if let errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            VStack(spacing: 12) {
                Button {
                    generateKey()
                } label: {
                    HStack {
                        if isWorking { ProgressView().padding(.trailing, 8) }
                        Text("Generate New Key")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isWorking)

                Button {
                    importFromClipboard()
                } label: {
                    Text("Import Secret Hex from Clipboard")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(isWorking)
            }
            .padding(.top, 8)

            Spacer()

            Text("Your private key is stored securely in the iOS Keychain.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .inlineNavigationTitle("Setup")
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
                app.refresh()
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
                app.refresh()
                onSuccess?()
            } catch {
                errorMessage = String(describing: error)
            }
            isWorking = false
        }
    }
}
