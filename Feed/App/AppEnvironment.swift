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
    let profileRepository: ProfileRepository
    let commentRepository: CommentRepository
    let scrapeRepository: ScrapeRepository
    let composerRepository: ComposerRepository
    let tasteRepository: TasteRepository
    let purchaseRepository: PurchaseRepository
    let discoverRepository: DiscoverRepository
    let mailProviders: [MailProvider]
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
            profileRepository = LiveProfileRepository(client: client)
            commentRepository = LiveCommentRepository(client: client)
            scrapeRepository = LiveScrapeRepository(client: client)
            composerRepository = LiveComposerRepository(client: client)
            tasteRepository = LiveTasteRepository(client: client)
            purchaseRepository = LivePurchaseRepository(client: client)
            discoverRepository = LiveDiscoverRepository(client: client)
            var providers: [MailProvider] = [GmailProvider(clientId: AppConfig.googleOAuthClientId)]
            if ProcessInfo.processInfo.arguments.contains("-fixture-mailbox") { providers.append(FixtureMailProvider()) }
            mailProviders = providers
            eventTracker = EventTracker(repository: LiveEventRepository(client: client))
            usingFixtures = false
        } else {
            client = nil
            auth = nil
            feedRepository = MockFeedRepository()
            socialRepository = MockSocialRepository()
            profileRepository = MockProfileRepository()
            commentRepository = MockCommentRepository()
            scrapeRepository = MockScrapeRepository()
            composerRepository = MockComposerRepository()
            tasteRepository = MockTasteRepository()
            purchaseRepository = MockPurchaseRepository()
            discoverRepository = MockDiscoverRepository()
            mailProviders = [FixtureMailProvider()]
            eventTracker = EventTracker(repository: MockEventRepository())
            usingFixtures = true
        }
        clickOut = ClickOutService(tracker: eventTracker, sessionId: sessionId, redirectBase: AppConfig.redirectBaseURL)
    }

    private(set) var me: Me?

    /// Establishes a session before any data loads.
    func start() async {
        if let auth { await auth.ensureSession() }
        await refreshMe()
        isReady = true
    }

    func refreshMe() async {
        me = try? await profileRepository.me()
    }

    var isAnonymous: Bool { auth?.state.isAnonymous ?? true }

    /// Show the quiz on first launch unless the account already completed it.
    var needsOnboarding: Bool {
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-skip-onboarding") { return false }
        if args.contains("-force-onboarding") { return true }
        if me?.onboarded == true { return false }
        return !UserDefaults.standard.bool(forKey: "onboarding.shown")
    }

    /// Returns true when the user may proceed; otherwise presents the sign-in sheet.
    func requireAccount(for reason: String) -> Bool {
        if auth == nil { return true } // fixtures: nothing to gate
        if isAnonymous { router.present(.auth(reason: reason)); return false }
        return true
    }

    func makeImpressionTracker() -> ImpressionTracker { ImpressionTracker(tracker: eventTracker, sessionId: sessionId) }
}
