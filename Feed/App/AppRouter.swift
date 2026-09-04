import SwiftUI

enum SheetRoute: Identifiable, Hashable {
    case comments(postId: UUID)
    case auth(reason: String)
    case productPicker(postId: UUID)
    case developerMenu

    var id: String {
        switch self {
        case .comments(let id): "comments-\(id)"
        case .auth(let r): "auth-\(r)"
        case .productPicker(let id): "products-\(id)"
        case .developerMenu: "dev"
        }
    }
}

enum CoverRoute: Identifiable, Hashable {
    case productBrowser(URL)
    case compose
    case onboarding
    case purchaseImport

    var id: String {
        switch self {
        case .productBrowser(let u): "browser-\(u.absoluteString)"
        case .compose: "compose"
        case .onboarding: "onboarding"
        case .purchaseImport: "purchase-import"
        }
    }
}

enum Route: Hashable {
    case profile(authorId: UUID)
    case post(postId: UUID)
    case pager(PostPagerPayload)
    case settings
    case importedPurchases
}

@MainActor
@Observable
final class AppRouter {
    var selectedTab: AppTab = .feed
    var feedPath = NavigationPath()
    var profilePath = NavigationPath()
    var sheet: SheetRoute?
    var cover: CoverRoute?

    func present(_ route: SheetRoute) { sheet = route }
    func present(_ route: CoverRoute) { cover = route }
    func openProduct(_ url: URL) { cover = .productBrowser(url) }
}
