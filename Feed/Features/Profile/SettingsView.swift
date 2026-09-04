import SwiftUI

struct SettingsView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(AppRouter.self) private var router
    @State private var versionTaps = 0

    var body: some View {
        List {
            Section("Account") {
                if let me = env.me {
                    LabeledContent("Status", value: me.isAnonymous ? "Guest" : "Signed in")
                    if let name = me.displayName { LabeledContent("Name", value: name) }
                }
                if env.isAnonymous {
                    Button("Sign in") { router.present(.auth(reason: "manage your account")) }
                } else {
                    Button("Sign out", role: .destructive) { Task { await env.auth?.signOut(); await env.refreshMe() } }
                }
            }
            Section("Taste") {
                Button("Redo the style quiz") { router.present(.onboarding) }
                NavigationLink("Imported purchases", value: Route.importedPurchases).accessibilityIdentifier("settings-imported-purchases")
            }
            Section("About") {
                LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")
                    .contentShape(Rectangle())
                    .onTapGesture { versionTaps += 1; if versionTaps >= 5 { router.present(.developerMenu); versionTaps = 0 } }
                LabeledContent("Data source", value: env.usingFixtures ? "Fixtures" : "Supabase")
            }
        }
        .navigationTitle("Settings")
        .scrollContentBackground(.hidden)
        .background(Theme.background)
    }
}

struct DeveloperMenuView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var pending = 0

    var body: some View {
        NavigationStack {
            List {
                Section("Session") {
                    LabeledContent("User", value: env.auth?.state.userId?.uuidString ?? "fixtures")
                    LabeledContent("Anonymous", value: env.isAnonymous ? "yes" : "no")
                    LabeledContent("Session id", value: env.sessionId.uuidString.prefix(8).description)
                    LabeledContent("Backend", value: AppConfig.supabaseURL?.host() ?? "none")
                }
                Section("Events") {
                    LabeledContent("Pending", value: String(pending))
                    Button("Flush now") { Task { await env.eventTracker.flush(); pending = await env.eventTracker.pendingCount } }
                }
                Section("Reset") {
                    Button("Sign out and start a new anonymous session", role: .destructive) { Task { await env.auth?.signOut(); await env.refreshMe() } }
                }
            }
            .navigationTitle("Developer")
            .task { pending = await env.eventTracker.pendingCount }
        }
    }
}
