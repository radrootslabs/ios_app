import SwiftUI

public struct CopyButton: View {
    private let value: String
    private let onCopied: (() -> Void)?
    @State private var copied = false

    public init(value: String, onCopied: (() -> Void)? = nil) {
        self.value = value
        self.onCopied = onCopied
    }

    public var body: some View {
        Button {
            Task { @MainActor in
                UIPasteboard.general.string = value
            }
            let gen = UINotificationFeedbackGenerator()
            gen.notificationOccurred(.success)
            withAnimation(.easeInOut(duration: 0.12)) { copied = true }
            onCopied?()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                withAnimation(.easeInOut(duration: 0.12)) { copied = false }
            }
        } label: {
            ZStack {
                Image(systemName: "doc.on.doc")
                    .opacity(copied ? 0 : 1)
                Image(systemName: "checkmark.circle.fill")
                    .opacity(copied ? 1 : 0)
            }
            .frame(width: 24, height: 24)
            .font(.system(size: 17, weight: .semibold))
        }
        .buttonStyle(.plain)
        .foregroundStyle(copied ? .green : .accentColor)
        .contentTransition(.opacity)
        .accessibilityLabel(copied ? "Copied" : "Copy")
    }
}
