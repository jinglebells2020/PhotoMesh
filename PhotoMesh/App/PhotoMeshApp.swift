import SwiftUI

@main
struct PhotoMeshApp: App {
    @State private var router = AppRouter()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // Must run before anything reads subscription state.
        Subscriptions.configure(apiKey: RevenueCatKey.public)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(router)
                .tint(PMTheme.accent)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Analytics.shared.track("app_open")
                Analytics.shared.flush()
            }
        }
    }
}
