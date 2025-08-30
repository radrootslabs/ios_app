import SwiftUI
import RadrootsKit

struct HomeView: View {
    @EnvironmentObject private var appState: AppState
    @State private var infoJSONString: String = "{}"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(Ls.appName)
                    .font(.largeTitle.bold())
                Text(infoJSONString)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(Color(.systemGray6))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .padding()
        }
        .navigationTitle(Ls.appName)
        .navigationBarTitleDisplayMode(.large)
        .task {
            infoJSONString = await appState.infoJSON()
        }
    }
}
