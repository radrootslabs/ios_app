import SwiftUI

public struct RadrootsProvider<Content: View>: View {
    @StateObject private var appState = AppState()
    private let onStartupError: ((Error) -> Void)?
    private let content: () -> Content

    public init(
        onStartupError: ((Error) -> Void)? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.onStartupError = onStartupError
        self.content = content
    }

    public var body: some View {
        content()
            .environmentObject(appState)
            .environmentObject(appState.keys)
            .environmentObject(appState.radroots)
            .task {
                do {
                    try await appState.start()
                } catch {
                    onStartupError?(error)
                }
            }
    }
}
