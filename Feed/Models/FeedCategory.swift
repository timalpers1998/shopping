import Foundation

/// The app is fashion-only for now, so the chips are just the two feeds.
/// Verticals (home, beauty) were removed from the UI; the backend enum still has them.
enum FeedCategory: String, CaseIterable, Identifiable, Codable, Sendable {
    case forYou = "for_you"
    case following

    var id: String { rawValue }

    var title: String {
        switch self {
        case .forYou: "For You"
        case .following: "Following"
        }
    }

    var requiresAccount: Bool { self == .following }
}
