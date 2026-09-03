import Foundation
import Nuke

extension ImagePipeline {
    /// Feed pipeline: aggressive disk cache independent of server headers, decoded-image memory cache.
    static let feed: ImagePipeline = {
        var config = ImagePipeline.Configuration.withDataCache(name: "feed-images", sizeLimit: 300 * 1024 * 1024)
        config.dataCachePolicy = .storeAll
        config.isProgressiveDecodingEnabled = true
        return ImagePipeline(configuration: config)
    }()
}

/// Prefetches the next few posts' cover and product images as the user scrolls.
final class FeedPrefetcher: Sendable {
    @ImagePipelineActor private static let prefetcher = ImagePrefetcher(pipeline: .feed)

    func update(posts: [Post], currentIndex: Int) {
        let window = posts.dropFirst(currentIndex + 1).prefix(3)
        var urls: [URL] = []
        for p in window {
            if let u = p.media.first?.url { urls.append(u) }
            for prod in p.products.prefix(3) { if let u = prod.imageUrl { urls.append(u) } }
        }
        Task { @ImagePipelineActor in
            Self.prefetcher.stopPrefetching()
            Self.prefetcher.startPrefetching(with: urls.map { ImageRequest(url: $0, processors: [.resize(width: 1080)]) })
        }
    }
}
