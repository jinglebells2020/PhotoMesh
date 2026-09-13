import SwiftUI

@main
struct PhotoMeshApp: App {
    @State private var router = AppRouter()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(router)
                .tint(PMTheme.accent)
        }
    }
}
