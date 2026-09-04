import Foundation
import Observation
import Supabase

/// Composition root. Built once at launch and injected into the SwiftUI environment.
@MainActor
@Observable
final class AppEnvironment {
    let sessionId = UUID()
    let feedRepository: FeedRepository
    let socialRepository: SocialRepository
    let eventTracker: EventTracker
    let clickOut: ClickOutService
    let router = AppRouter()
    let auth: AuthService?
    let client: SupabaseClient?
    let usingFixtures: Bool
    private(set) var isReady = false

    init() {
        if let url = AppConfig.supabaseURL, let key = AppConfig.supabaseAnonKey, !ProcessInfo.processInfo.arguments.contains("-use-fixtures") {
            let client = SupabaseClientFactory.make(url: url, anonKey: key)
            self.client = client
            auth = AuthService(client: client)
            feedRepository = LiveFeedRepository(client: client)
            socialRepository = LiveSocialRepository(client: client)
            eventTracker = EventTracker(repository: LiveEventRepository(client: client))
            usingFixtures = false
        } else {
            client = nil
            auth = nil
            feedRepository = MockFeedRepository()
            socialRepository = MockSocialRepository()
            eventTracker = EventTracker(repository: MockEventRepository())
            usingFixtures = true
        }
        clickOut = ClickOutService(tracker: eventTracker, sessionId: sessionId, redirectBase: AppConfig.redirectBaseURL)
    }

    /// Establishes a session before any data loads.
    func start() async {
        if let auth { await auth.ensureSession() }
        isReady = true
    }

    func makeImpressionTracker() -> ImpressionTracker { ImpressionTracker(tracker: eventTracker, sessionId: sessionId) }
}
