import SwiftUI
import RadrootsKit

struct SetupView: View {
    @EnvironmentObject private var app: Radroots
    @EnvironmentObject private var keys: RadrootsKeys
    @State private var busy = false
    @State private var errorText: String?

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            VStack(spacing: 8) {
                Text(Ls.setupGreetingHeader)
                    .font(.largeTitle).bold()
                Text(Ls.setupGreetingHeaderSub)
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 24)
            }

            Button {
                generate()
            } label: {
                HStack {
                    if busy { ProgressView().tint(.white) }
                    Text(busy ? "Generating…" : "Generate & Save Keypair")
                        .bold()
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(busy ? Color.gray : Color.accentColor)
                .foregroundColor(.white)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .disabled(busy)
            .padding(.horizontal, 24)

            if let npub = keys.npub {
                Text("Public key")
                    .font(.caption).foregroundColor(.secondary)
                Text(npub)
                    .font(.footnote)
                    .multilineTextAlignment(.center)
                    .textSelection(.enabled)
                    .padding(.horizontal, 24)
            }

            Spacer()
        }
        .padding(.vertical, 16)
        .alert("Key Generation Failed", isPresented: Binding(
            get: { errorText != nil },
            set: { _ in errorText = nil }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorText ?? "")
        }
    }

    @MainActor
    private func generate() {
        busy = true
        Task {
            defer { busy = false }
            do {
                if app.runtime == nil {
                    try app.start() // ensure net-core runtime exists for key ops
                }
                guard let rt = app.runtime else {
                    throw NSError(domain: "Radroots", code: -1, userInfo: [NSLocalizedDescriptionKey: "Runtime not initialized."])
                }
                try keys.generateAndPersist(runtime: rt) // saves in Keychain and sets active profile
            } catch {
                errorText = String(describing: error)
            }
        }
    }
}
