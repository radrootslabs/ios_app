import SwiftUI

public struct CopyRow: View {
    private let title: String
    private let value: String
    private let onCopied: (() -> Void)?

    public init(title: String, value: String, onCopied: (() -> Void)? = nil) {
        self.title = title
        self.value = value
        self.onCopied = onCopied
    }

    public var body: some View {
        LabeledContent(title) {
            HStack(spacing: 6) {
                Text(value)
                    .font(.callout.monospaced())
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                CopyButton(value: value, onCopied: onCopied)
            }
        }
    }
}
