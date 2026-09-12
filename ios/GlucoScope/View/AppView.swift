import SwiftUI

struct AppView: View {
    @ObservedObject var runtime: AppRuntime

    var body: some View {
        Group {
            switch runtime.mode {
            case nil:
                ModeChoiceView(choose: runtime.choose)
            case .viewer:
                NavigationStack {
                    if runtime.viewerDataSource.datasource == nil {
                        OnboardingWizard(runtime.viewerDataSource)
                    } else {
                        MainView()
                    }
                }
            case .standalone:
                if runtime.preferences.standaloneOnboardingCompleted {
                    StandaloneRootView(
                        glucose: runtime.glucose,
                        selectedTab: $runtime.standaloneTab
                    ) {
                        StandaloneSettingsView(runtime: runtime)
                    }
                } else {
                    StandaloneOnboardingView(glucose: runtime.glucose)
                }
            }
        }
        .task { await runtime.start() }
        .onOpenURL { url in
            guard url.scheme == "glucoscope",
                  url.host == "graph",
                  runtime.mode == .standalone else { return }
            runtime.standaloneTab = .graph
        }
        .alert("Uploads are still pending", isPresented: $runtime.showPendingUploadWarning) {
            Button("Stay in Bluetooth mode", role: .cancel) { }
            Button("Switch and pause uploads", role: .destructive) {
                runtime.confirmViewerMode()
            }
        } message: {
            Text("\(runtime.uploads.pendingReadingCount) readings are waiting to upload. They will remain queued and resume when you return to Bluetooth mode.")
        }
    }
}
