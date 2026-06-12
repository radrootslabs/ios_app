import SwiftUI

struct SetupView: View {
    @EnvironmentObject private var app: AppState

    var onSuccess: (() -> Void)? = nil

    @State private var step: Step = .welcome
    @State private var username = ""
    @State private var code = ""
    @State private var challenge: FieldLoginChallenge?
    @State private var isWorking = false
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            switch step {
            case .welcome:
                SetupWelcomeView {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        step = .login
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .leading)))
            case .login:
                SetupLoginView(
                    username: $username,
                    isWorking: isWorking,
                    errorMessage: errorMessage,
                    onSubmit: startLogin
                )
                .transition(.opacity.combined(with: .move(edge: .trailing)))
            case .verify:
                SetupVerifyView(
                    code: $code,
                    challenge: challenge,
                    isWorking: isWorking,
                    errorMessage: errorMessage,
                    onVerify: verifyLogin,
                    onResend: resendCode
                )
                .transition(.opacity.combined(with: .move(edge: .trailing)))
            }
        }
        .animation(.easeInOut(duration: 0.25), value: step)
        .toolbar(.hidden, for: .navigationBar)
        .accessibilityIdentifier("field_ios.setup")
    }

    private func startLogin() {
        errorMessage = nil
        isWorking = true
        Task { @MainActor in
            do {
                challenge = try app.startLogin(username: username)
                code = ""
                step = .verify
            } catch {
                errorMessage = error.localizedDescription
            }
            isWorking = false
        }
    }

    private func resendCode() {
        guard let challenge else { return }
        errorMessage = nil
        isWorking = true
        Task { @MainActor in
            do {
                self.challenge = try app.resendLoginChallenge(challengeId: challenge.id)
            } catch {
                errorMessage = error.localizedDescription
            }
            isWorking = false
        }
    }

    private func verifyLogin() {
        guard let challenge else { return }
        errorMessage = nil
        isWorking = true
        Task { @MainActor in
            do {
                try app.verifyLogin(challengeId: challenge.id, code: code)
                onSuccess?()
            } catch {
                errorMessage = error.localizedDescription
            }
            isWorking = false
        }
    }
}

private enum Step {
    case welcome
    case login
    case verify
}

private struct SetupWelcomeView: View {
    let onContinue: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "person.badge.key.fill")
                .font(.system(size: 72, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 120, height: 120)

            Text(Ls.setupGreetingHeader)
                .font(.title.weight(.semibold))
                .multilineTextAlignment(.center)

            Text("Sign in to your Radroots account to prepare the field runtime.")
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

private struct SetupLoginView: View {
    @Binding var username: String
    let isWorking: Bool
    let errorMessage: String?
    let onSubmit: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            VStack(spacing: 10) {
                Image(systemName: "envelope.badge.shield.half.filled")
                    .font(.system(size: 44, weight: .semibold))
                    .foregroundStyle(.secondary)

                Text("Sign in")
                    .font(.title2.weight(.semibold))
                    .multilineTextAlignment(.center)

                Text("Enter your Radroots username to receive a verification code.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            TextField("Username", text: $username)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .textContentType(.username)
                .keyboardType(.emailAddress)
                .padding(14)
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .accessibilityIdentifier("field_ios.setup.username")

            SetupErrorText(errorMessage)

            if isWorking {
                ProgressView()
                    .controlSize(.large)
            }

            Button {
                onSubmit()
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "paperplane.fill")
                    Text("Send Code")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(isWorking || username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .accessibilityIdentifier("field_ios.setup.start_login")

            Spacer()
        }
        .padding()
        .accessibilityIdentifier("field_ios.setup.login")
    }
}

private struct SetupVerifyView: View {
    @Binding var code: String
    let challenge: FieldLoginChallenge?
    let isWorking: Bool
    let errorMessage: String?
    let onVerify: () -> Void
    let onResend: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            VStack(spacing: 10) {
                Image(systemName: "checkmark.shield.fill")
                    .font(.system(size: 44, weight: .semibold))
                    .foregroundStyle(.secondary)

                Text("Enter verification code")
                    .font(.title2.weight(.semibold))
                    .multilineTextAlignment(.center)

                if let challenge {
                    Text("We sent a code to \(challenge.maskedEmail).")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
            }

            TextField("Code", text: $code)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .textContentType(.oneTimeCode)
                .keyboardType(.numberPad)
                .padding(14)
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .accessibilityIdentifier("field_ios.setup.code")

            SetupErrorText(errorMessage)

            if isWorking {
                ProgressView()
                    .controlSize(.large)
            }

            VStack(spacing: 12) {
                Button {
                    onVerify()
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "checkmark.circle.fill")
                        Text("Verify")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(isWorking || code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityIdentifier("field_ios.setup.verify_login")

                Button {
                    onResend()
                } label: {
                    Text("Resend Code")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .disabled(isWorking || challenge == nil)
                .accessibilityIdentifier("field_ios.setup.resend_code")
            }

            Spacer()
        }
        .padding()
        .accessibilityIdentifier("field_ios.setup.verify")
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
