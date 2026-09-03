import Foundation

enum FeedCategory: String, CaseIterable, Identifiable, Codable, Sendable {
    case forYou = "for_you"
    case following
    case fashion
    case home
    case beauty

    var id: String { rawValue }

    var title: String {
        switch self {
        case .forYou: "For You"
        case .following: "Following"
        case .fashion: "Fashion"
        case .home: "Home"
        case .beauty: "Beauty"
        }
    }

    var requiresAccount: Bool { self == .following }
}
