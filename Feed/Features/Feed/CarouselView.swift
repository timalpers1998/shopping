import SwiftUI
import NukeUI

struct CarouselView: View {
    let media: [Media]
    @Binding var index: Int

    var body: some View {
        TabView(selection: $index) {
            ForEach(Array(media.enumerated()), id: \.element.id) { i, m in
                FeedImage(url: m.url, isPortrait: m.isPortrait).tag(i)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .ignoresSafeArea()
    }
}

struct CarouselDots: View {
    let count: Int
    let index: Int
    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<count, id: \.self) { i in
                Capsule().fill(.white.opacity(i == index ? 1 : 0.4)).frame(width: 14, height: 3)
            }
        }
    }
}

/// Full-bleed feed image with Nuke caching and a neutral placeholder.
struct FeedImage: View {
    let url: URL?
    var isPortrait = true

    var body: some View {
        GeometryReader { geo in
            LazyImage(url: url) { state in
                if let image = state.image {
                    image.resizable()
                        .aspectRatio(contentMode: isPortrait ? .fill : .fit)
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                } else {
                    Rectangle().fill(Theme.surface).shimmer()
                }
            }
            .pipeline(.feed)
            .processors([.resize(width: 1080)])
        }
        .ignoresSafeArea()
    }
}
