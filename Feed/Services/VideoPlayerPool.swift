import Foundation
import AVFoundation
import Observation

@MainActor
@Observable
final class PlaybackSettings {
    static let shared = PlaybackSettings()
    var isMuted = true {
        didSet { Self.configureAudioSession(muted: isMuted) }
    }

    static func configureAudioSession(muted: Bool) {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(muted ? .ambient : .playback, mode: .moviePlayback, options: muted ? [.mixWithOthers] : [])
        try? session.setActive(true)
    }
}

/// A small pool of AVPlayers: the active post plays, its neighbours preload, everything else is released.
@MainActor
final class VideoPlayerPool {
    private struct Lease { let player: AVPlayer; var url: URL; var endObserver: NSObjectProtocol? }
    private var leases: [UUID: Lease] = [:]
    private var free: [AVPlayer] = []
    private let capacity = 3
    var onLoop: ((UUID) -> Void)?

    init() {
        for _ in 0..<capacity {
            let p = AVPlayer()
            p.automaticallyWaitsToMinimizeStalling = true
            p.actionAtItemEnd = .none
            free.append(p)
        }
    }

    func player(for postId: UUID) -> AVPlayer? { leases[postId]?.player }

    /// Keeps players for `keep` (active first), releasing the rest.
    func assign(keep posts: [(id: UUID, url: URL)], active: UUID?) {
        let keepIds = Set(posts.map(\.id))
        for id in leases.keys where !keepIds.contains(id) { release(id) }
        for (id, url) in posts where leases[id] == nil {
            guard let player = free.popLast() else { break }
            let item = AVPlayerItem(url: url)
            item.preferredForwardBufferDuration = id == active ? 0 : 3
            player.replaceCurrentItem(with: item)
            player.isMuted = PlaybackSettings.shared.isMuted
            let observer = NotificationCenter.default.addObserver(forName: AVPlayerItem.didPlayToEndTimeNotification, object: item, queue: .main) { [weak self, weak player] _ in
                Task { @MainActor in
                    player?.seek(to: .zero)
                    player?.play()
                    self?.onLoop?(id)
                }
            }
            leases[id] = Lease(player: player, url: url, endObserver: observer)
        }
        for (id, lease) in leases {
            lease.player.isMuted = PlaybackSettings.shared.isMuted
            if id == active { lease.player.play() } else { lease.player.pause() }
        }
    }

    func pauseAll() { for l in leases.values { l.player.pause() } }
    func resume(_ id: UUID) { leases[id]?.player.play() }

    func setMuted(_ muted: Bool) { for l in leases.values { l.player.isMuted = muted } }

    private func release(_ id: UUID) {
        guard let lease = leases.removeValue(forKey: id) else { return }
        if let o = lease.endObserver { NotificationCenter.default.removeObserver(o) }
        lease.player.pause()
        lease.player.replaceCurrentItem(with: nil)
        free.append(lease.player)
    }

    func releaseAll() { for id in Array(leases.keys) { release(id) } }
}
