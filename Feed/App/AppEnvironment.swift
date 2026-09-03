import Foundation
import Observation

/// Composition root. Built once at launch and injected into the SwiftUI environment.
@MainActor
@Observable
final class AppEnvironment {
    let sessionId = UUID()
    let feedRepository: FeedRepository
    let eventTracker: EventTracker
    let clickOut: ClickOutService
    let router = AppRouter()
    let usingFixtures: Bool

    init() {
        // Until M2 wires Supabase, everything runs on fixtures.
        usingFixtures = true
        feedRepository = MockFeedRepository()
        eventTracker = EventTracker(repository: MockEventRepository())
        clickOut = ClickOutService(tracker: eventTracker, sessionId: sessionId, redirectBase: AppConfig.redirectBaseURL)
    }

    func makeImpressionTracker() -> ImpressionTracker { ImpressionTracker(tracker: eventTracker, sessionId: sessionId) }
}
