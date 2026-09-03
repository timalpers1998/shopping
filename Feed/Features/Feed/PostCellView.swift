import SwiftUI

struct PostCellView: View {
    let post: Post
    let index: Int
    let isActive: Bool
    let model: FeedViewModel
    @State private var mediaIndex = 0

    var body: some View {
        ZStack(alignment: .bottom) {
            PostMediaView(post: post, isActive: isActive, mediaIndex: $mediaIndex)
                .onChange(of: mediaIndex) { _, i in if isActive { model.impressions.mediaShown(index: i) } }

            LinearGradient(colors: [.clear, .black.opacity(0.75)], startPoint: .init(x: 0.5, y: 0.45), endPoint: .bottom)
                .allowsHitTesting(false)

            VStack(alignment: .leading, spacing: 10) {
                if post.kind == .carousel && post.media.count > 1 {
                    CarouselDots(count: post.media.count, index: mediaIndex)
                }
                HStack(alignment: .bottom, spacing: 10) {
                    PostOverlayView(post: post, model: model)
                    ActionRailView(post: post, model: model).frame(width: 56)
                }
            }
            .padding(.leading, 12)
            .padding(.trailing, 8)
            .padding(.bottom, 96)
        }
        .background(Theme.background)
        .clipped()
    }
}

struct PostMediaView: View {
    let post: Post
    let isActive: Bool
    @Binding var mediaIndex: Int

    var body: some View {
        switch post.kind {
        case .image:
            FeedImage(url: post.media.first?.url, isPortrait: post.media.first?.isPortrait ?? true)
        case .carousel:
            CarouselView(media: post.media, index: $mediaIndex)
        case .video:
            // Video playback lands in M5; until then show the poster with a play badge.
            FeedImage(url: post.media.first?.thumbnailUrl ?? post.media.first?.url, isPortrait: true)
                .overlay(alignment: .topTrailing) {
                    Label("Video", systemImage: "play.fill").font(.caption.bold()).padding(8)
                        .background(.ultraThinMaterial, in: Capsule()).padding(.top, 60).padding(.trailing, 12)
                }
        }
    }
}
