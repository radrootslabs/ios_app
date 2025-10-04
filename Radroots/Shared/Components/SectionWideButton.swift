import SwiftUI

public struct SectionWideButton: View {
    private let title: String
    private let enabled: Bool
    private let isProminent: Bool
    private let action: () -> Void

    public init(
        _ title: String,
        enabled: Bool = true,
        isProminent: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.enabled = enabled
        self.isProminent = isProminent
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Text(title)
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
        .foregroundStyle(foregroundStyle)
        .disabled(!enabled)
        .listRowBackground(backgroundStyle)
        .animation(.easeInOut(duration: 0.15), value: isProminent)
        .accessibilityAddTraits(.isButton)
    }

    private var backgroundStyle: Color {
        guard enabled else { return Color.secondary.opacity(0.25) }
        return isProminent ? .accentColor : Color.secondary.opacity(0.15)
    }

    private var foregroundStyle: Color {
        guard enabled else { return .secondary }
        return isProminent ? .white : .primary
    }
}
