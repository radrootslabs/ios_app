import SwiftUI

struct SetupView: View {
    @EnvironmentObject private var app: AppState

    var onSuccess: (() -> Void)? = nil

    @State private var secretKey = ""
    @State private var isWorking = false
    @State private var errorMessage: String?
    @State private var showImport = false
    @FocusState private var secretFocused: Bool

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Spacer(minLength: 40)

                Image(systemName: app.hasKey ? "lock.open.fill" : "key.radiowaves.forward.fill")
                    .font(.system(size: 64, weight: .semibold))
                    .foregroundStyle(.green)
                    .frame(width: 112, height: 112)

                VStack(spacing: 8) {
                    Text(app.hasKey ? "Identity saved on this iPhone" : "Create a Nostr identity")
                        .font(.title.weight(.semibold))
                        .multilineTextAlignment(.center)

                    if let npub = app.npub {
                        Text(npub)
                            .font(.footnote.monospaced())
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .textSelection(.enabled)
                    } else {
                        Text("Radroots uses a local Nostr identity to publish and read field events.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }

                SetupErrorText(errorMessage)

                if isWorking {
                    ProgressView()
                        .controlSize(.large)
                }

                if app.hasKey {
                    Button {
                        continueWithIdentity()
                    } label: {
                        Label("Unlock Identity", systemImage: "lock.open.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(isWorking)
                    .accessibilityIdentifier("field_ios.setup.continue")
                } else {
                    Button {
                        createIdentity()
                    } label: {
                        Label("Create Identity", systemImage: "plus.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(isWorking)
                    .accessibilityIdentifier("field_ios.setup.create_identity")

                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showImport.toggle()
                            secretFocused = showImport
                        }
                    } label: {
                        Label("Import Secret Key", systemImage: "square.and.arrow.down")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .disabled(isWorking)
                    .accessibilityIdentifier("field_ios.setup.import_identity")

                    if showImport {
                        VStack(spacing: 12) {
                            SecureField("nsec or hex secret key", text: $secretKey)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .focused($secretFocused)
                                .padding(14)
                                .background(Color(.secondarySystemGroupedBackground))
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                .accessibilityIdentifier("field_ios.setup.secret_key")

                            Button {
                                importIdentity()
                            } label: {
                                Label("Import Identity", systemImage: "checkmark.circle.fill")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                            .disabled(
                                isWorking ||
                                secretKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            )
                            .accessibilityIdentifier("field_ios.setup.use_secret_key")
                        }
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }

                Spacer(minLength: 24)
            }
            .padding()
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
        .background(Color(.systemGroupedBackground))
        .toolbar(.hidden, for: .navigationBar)
        .accessibilityIdentifier("field_ios.setup")
    }

    private func continueWithIdentity() {
        errorMessage = nil
        isWorking = true
        Task {
            do {
                try await app.continueWithLocalIdentity()
                onSuccess?()
            } catch {
                errorMessage = error.localizedDescription
            }
            isWorking = false
        }
    }

    private func createIdentity() {
        errorMessage = nil
        isWorking = true
        Task {
            do {
                try await app.createLocalIdentity()
                onSuccess?()
            } catch {
                errorMessage = error.localizedDescription
            }
            isWorking = false
        }
    }

    private func importIdentity() {
        errorMessage = nil
        isWorking = true
        let submittedSecret = secretKey
        secretKey = ""
        Task {
            do {
                try await app.importNostrSecret(submittedSecret)
                onSuccess?()
            } catch {
                errorMessage = error.localizedDescription
            }
            isWorking = false
        }
    }
}

private struct SetupErrorText: View {
    let message: String?

    init(_ message: String?) {
        self.message = message
    }

    var body: some View {
        if let message {
            Text(message)
                .foregroundStyle(.red)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
                .accessibilityIdentifier("field_ios.setup.error")
        }
    }
}
