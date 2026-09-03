import SwiftUI
import NukeUI

struct AvatarView: View {
    let url: URL?
    var size: CGFloat = 40
    var body: some View {
        LazyImage(url: url) { state in
            if let image = state.image {
                image.resizable().scaledToFill()
            } else {
                Circle().fill(Theme.surfaceElevated)
                    .overlay(Image(systemName: "person.fill").foregroundStyle(.white.opacity(0.6)))
            }
        }
        .pipeline(.feed)
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().stroke(.white, lineWidth: 1.5))
    }
}
