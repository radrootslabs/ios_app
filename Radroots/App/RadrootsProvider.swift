import SwiftUI
import UIKit

public struct RadrootsProvider<Content: View>: View {
    @Environment(\.scenePhase) private var scenePhase
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
            .environmentObject(appState.radroots)
            .task {
                do {
                    try await appState.start()
                } catch {
                    onStartupError?(error)
                }
            }
            .onChange(of: scenePhase) { _, phase in
                switch phase {
                case .active:
                    appState.appDidBecomeActive()
                case .background:
                    appState.appDidEnterBackground()
                case .inactive:
                    break
                @unknown default:
                    break
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.willTerminateNotification)) { _ in
                Task { await appState.shutdown() }
            }
            .onDisappear {
                Task { await appState.shutdown() }
            }
    }
}
