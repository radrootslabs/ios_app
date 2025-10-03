import SwiftUI

public struct RadrootsProvider<Content: View>: View {
    @StateObject private var appState = AppState()
    private let content: () -> Content

    public init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    public var body: some View {
        Group { content() }
            .environmentObject(appState)
            .environmentObject(appState.keys)
            .environmentObject(appState.radroots)
            .task { try? appState.start() }
    }
}