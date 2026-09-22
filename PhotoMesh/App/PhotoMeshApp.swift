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
            switch phase {
            case .active:
                if Analytics.shared.becameActive() { Analytics.shared.track("first_open") }
                Analytics.shared.track("app_open")
                Analytics.shared.flush()
            case .background:
                if let seconds = Analytics.shared.becameInactive() {
                    Analytics.shared.track("app_background", ["active_seconds": .init(seconds)])
                }
                Analytics.shared.flush()
            default:
                break
            }
        }
    }
}
