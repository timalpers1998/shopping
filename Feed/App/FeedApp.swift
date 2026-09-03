import SwiftUI

@main
struct FeedApp: App {
    @State private var environment = AppEnvironment()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            MainTabView()
                .environment(environment)
                .environment(environment.router)
                .preferredColorScheme(.dark)
                .onChange(of: scenePhase) { _, phase in
                    if phase == .background { Task { await environment.eventTracker.flush() } }
                }
        }
    }
}
