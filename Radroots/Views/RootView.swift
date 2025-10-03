import SwiftUI
import RadrootsKit

struct RootView: View {
    @EnvironmentObject private var app: AppState

    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink("Settings") {
                        SettingsView()
                    }
                    NavigationLink("Setup") {
                        SetupView()
                    }
                }
            }
            .navigationTitle("Radroots")
        }
        .onAppear { app.refresh() }
        .applyKeyChangeHandler(app: app)
    }
}

private extension View {
    @ViewBuilder
    func applyKeyChangeHandler(app: AppState) -> some View {
        if #available(iOS 17.0, *) {
            self.onChange(of: app.hasKey) { _, newValue in
                if newValue { app.refresh() }
            }
        } else {
            self.onChange(of: app.hasKey) { _ in
                app.refresh()
            }
        }
    }
}
