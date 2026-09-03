import SwiftUI

enum AppTab: Hashable {
    case feed, discover, compose, activity, profile
}

struct MainTabView: View {
    @State private var selection: AppTab = .feed

    var body: some View {
        TabView(selection: $selection) {
            PlaceholderScreen(title: "Feed")
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
    }
}

private struct PlaceholderScreen: View {
    let title: String
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            Text(title).font(.largeTitle.bold()).foregroundStyle(.white)
        }
    }
}
