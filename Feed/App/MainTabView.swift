import SwiftUI

enum AppTab: Hashable {
    case feed, discover, compose, activity, profile
}

struct MainTabView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(AppRouter.self) private var router
    @State private var feedModel: FeedViewModel?

    var body: some View {
        @Bindable var router = router
        let selection = Binding<AppTab>(
            get: { router.selectedTab },
            set: { tab in
                if tab == .compose {
                    if env.requireAccount(for: "post") { router.present(.compose) }
                } else { router.selectedTab = tab }
            }
        )
        TabView(selection: selection) {
            Group {
                if let feedModel {
                    NavigationStack(path: $router.feedPath) {
                        FeedView(model: feedModel)
                            .navigationDestination(for: Route.self) { RouteView(route: $0) }
                    }
                } else {
                    Color.black
                }
            }
            .tabItem { Label("Home", systemImage: "house.fill") }
            .tag(AppTab.feed)

            NavigationStack(path: $router.feedPath) {
                DiscoverView()
                    .navigationDestination(for: Route.self) { RouteView(route: $0) }
            }
            .tabItem { Label("Discover", systemImage: "magnifyingglass") }
            .tag(AppTab.discover)
            PlaceholderScreen(title: "Compose")
                .tabItem { Label("", systemImage: "plus.app.fill") }
                .tag(AppTab.compose)
            PlaceholderScreen(title: "Activity")
                .tabItem { Label("Activity", systemImage: "heart") }
                .tag(AppTab.activity)
            NavigationStack(path: $router.profilePath) {
                OwnProfileView()
                    .navigationDestination(for: Route.self) { RouteView(route: $0) }
            }
            .tabItem { Label("Profile", systemImage: "person") }
            .tag(AppTab.profile)
        }
        .tint(.white)
        .toolbarBackground(.black, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
        .sheet(item: $router.sheet) { route in
            switch route {
            case .comments(let id):
                CommentsSheetView(postId: id) { delta in feedModel?.adjustCommentCount(postId: id, by: delta) }
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            case .auth(let reason): AuthSheetView(reason: reason).presentationDetents([.large])
            case .productPicker(let id): ProductPickerSheet(postId: id).presentationDetents([.medium, .large])
            case .developerMenu: DeveloperMenuView()
            }
        }
        .fullScreenCover(item: $router.cover) { route in
            switch route {
            case .productBrowser(let url): ProductBrowserView(url: url).ignoresSafeArea()
            case .compose: ComposeFlowView { post in feedModel?.insertNewPost(post) }
            case .onboarding:
                OnboardingFlowView { submitted in
                    router.cover = nil
                    if submitted, !ProcessInfo.processInfo.arguments.contains("-skip-purchase-import"), !env.mailProviders.filter(\.isAvailable).isEmpty {
                        Task { try? await Task.sleep(for: .milliseconds(350)); router.present(.purchaseImport) }
                    } else {
                        Task { await feedModel?.store.refresh(); if let s = feedModel?.store { feedModel?.activePostChanged(in: s) } }
                    }
                }
            case .purchaseImport:
                PurchaseImportFlowView { _ in
                    router.cover = nil
                    Task { await feedModel?.store.refresh(); if let s = feedModel?.store { feedModel?.activePostChanged(in: s) } }
                }
            }
        }
        .task {
            await env.start()
            if feedModel == nil { feedModel = FeedViewModel(environment: env) }
            if env.needsOnboarding { router.present(.onboarding) }
        }
        .onOpenURL { url in Task { await env.auth?.handle(url: url) } }
        .onChange(of: router.selectedTab) { _, tab in feedModel?.isVisible = (tab == .feed) }
    }
}

struct RouteView: View {
    let route: Route
    var body: some View {
        switch route {
        case .profile(let id): ProfileView(authorId: id)
        case .post(let id): PlaceholderScreen(title: "Post \(id.uuidString.prefix(6))")
        case .pager(let payload): PostPagerView(payload: payload)
        case .settings: SettingsView()
        case .importedPurchases: ImportedPurchasesView()
        }
    }
}

struct PlaceholderScreen: View {
    let title: String
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            Text(title).font(.largeTitle.bold()).foregroundStyle(.white)
        }
    }
}
