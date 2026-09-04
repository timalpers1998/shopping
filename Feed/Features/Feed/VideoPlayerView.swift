import SwiftUI
import AVFoundation
import NukeUI

/// AVPlayerLayer-backed view. Shows the poster until playback is actually running.
struct VideoPlayerView: View {
    let post: Post
    let player: AVPlayer?
    let isActive: Bool
    @State private var isPlaying = false
    @State private var showMuteGlyph = false
    private var settings: PlaybackSettings { PlaybackSettings.shared }

    var body: some View {
        ZStack {
            if let player {
                PlayerLayerView(player: player, gravity: (post.media.first?.isPortrait ?? true) ? .resizeAspectFill : .resizeAspect)
                    .ignoresSafeArea()
                    .onReceive(player.publisher(for: \.timeControlStatus)) { status in
                        withAnimation(.easeOut(duration: 0.15)) { isPlaying = status == .playing }
                    }
            }
            FeedImage(url: post.media.first?.thumbnailUrl ?? post.media.first?.url, isPortrait: post.media.first?.isPortrait ?? true)
                .opacity(isPlaying ? 0 : 1)
                .allowsHitTesting(false)
            if showMuteGlyph {
                Image(systemName: settings.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .font(.system(size: 34, weight: .bold)).foregroundStyle(.white)
                    .padding(22).background(.black.opacity(0.45), in: Circle())
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            settings.isMuted.toggle()
            player?.isMuted = settings.isMuted
            withAnimation(.spring(duration: 0.25)) { showMuteGlyph = true }
            Task { try? await Task.sleep(for: .milliseconds(700)); withAnimation { showMuteGlyph = false } }
        }
        .accessibilityIdentifier("video-player")
        .accessibilityLabel(settings.isMuted ? "Video, muted. Tap to unmute" : "Video. Tap to mute")
    }
}

struct PlayerLayerView: UIViewRepresentable {
    let player: AVPlayer
    let gravity: AVLayerVideoGravity

    final class PlayerUIView: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }

    func makeUIView(context: Context) -> PlayerUIView {
        let v = PlayerUIView()
        v.backgroundColor = .clear
        v.playerLayer.player = player
        v.playerLayer.videoGravity = gravity
        return v
    }

    func updateUIView(_ uiView: PlayerUIView, context: Context) {
        if uiView.playerLayer.player !== player { uiView.playerLayer.player = player }
        uiView.playerLayer.videoGravity = gravity
    }
}
