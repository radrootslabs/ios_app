import SwiftUI

struct ToastModifier<Overlay: View>: ViewModifier {
    @Binding var isPresented: Bool
    let autoDismiss: Double
    let overlay: () -> Overlay

    func body(content: Content) -> some View {
        ZStack {
            content
            if isPresented {
                overlay()
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
                    .zIndex(1)
                    .onAppear {
                        guard autoDismiss > 0 else { return }
                        DispatchQueue.main.asyncAfter(deadline: .now() + autoDismiss) {
                            withAnimation { isPresented = false }
                        }
                    }
            }
        }
        .animation(.easeInOut(duration: 0.15), value: isPresented)
    }
}

extension View {
    func toast<Overlay: View>(
        isPresented: Binding<Bool>,
        autoDismiss: Double = 1.2,
        @ViewBuilder overlay: @escaping () -> Overlay
    ) -> some View {
        modifier(
            ToastModifier(
                isPresented: isPresented,
                autoDismiss: autoDismiss,
                overlay: overlay
            )
        )
    }
}
