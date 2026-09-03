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
                if tab == .compose { router.present(.compose) } else { router.selectedTab = tab }
            }
        )
        TabView(selection: selection) {
            Group {
                if let feedModel {
                    NavigationStack(path: $router.feedPath) {
                        FeedView(model: feedModel)
                            .navigationDestination(for: Route.self) { route in
                                switch route {
                                case .profile(let id): PlaceholderScreen(title: "Profile \(id.uuidString.prefix(6))")
                                case .post(let id): PlaceholderScreen(title: "Post \(id.uuidString.prefix(6))")
                                }
                            }
                    }
                } else {
                    Color.black
                }
            }
            .tabItem { Label("Home", systemImage: "house.fill") }
            .tag(AppTab.feed)

            PlaceholderScreen(title: "Discover")
                .tabItem { Label("Discover", systemImage: "magnifyingglass") }
                .tag(AppTab.discover)
            PlaceholderScreen(title: "Compose")
                .tabItem { Label("", systemImage: "plus.app.fill") }
                .tag(AppTab.compose)
            PlaceholderScreen(title: "Activity")
                .tabItem { Label("Activity", systemImage: "heart") }
                .tag(AppTab.activity)
            PlaceholderScreen(title: "Profile")
                .tabItem { Label("Profile", systemImage: "person") }
                .tag(AppTab.profile)
        }
        .tint(.white)
        .toolbarBackground(.black, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
        .sheet(item: $router.sheet) { route in
            switch route {
            case .comments(let id): PlaceholderScreen(title: "Comments \(id.uuidString.prefix(6))").presentationDetents([.medium, .large])
            case .auth(let reason): PlaceholderScreen(title: "Sign in to \(reason)").presentationDetents([.medium])
            case .productPicker(let id): ProductPickerSheet(postId: id).presentationDetents([.medium, .large])
            case .developerMenu: PlaceholderScreen(title: "Developer")
            }
        }
        .fullScreenCover(item: $router.cover) { route in
            switch route {
            case .productBrowser(let url): ProductBrowserView(url: url).ignoresSafeArea()
            case .compose: PlaceholderScreen(title: "Compose (M4)").overlay(alignment: .topTrailing) {
                Button("Close") { router.cover = nil }.padding()
            }
            }
        }
        .task {
            if feedModel == nil { feedModel = FeedViewModel(environment: env) }
        }
        .onChange(of: router.selectedTab) { _, tab in feedModel?.isVisible = (tab == .feed) }
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
