import Foundation
import UIKit
import ImageIO
import UniformTypeIdentifiers
import AVFoundation
import CoreTransferable

enum ImageResizer {
    /// Downsamples to `maxPixel` on the long edge, honouring EXIF orientation, and returns JPEG data plus size.
    nonisolated static func jpeg(from data: Data, maxPixel: Int, quality: CGFloat = 0.85) -> (Data, Int, Int)? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { return nil }
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(out, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, cg, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return (out as Data, cg.width, cg.height)
    }
}

/// Transferable wrapper that copies a picked video into our temp directory (the picker's URL is only valid inside the closure).
struct VideoFile: Transferable {
    let url: URL
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { file in
            SentTransferredFile(file.url)
        } importing: { received in
            let dir = FileManager.default.temporaryDirectory.appending(path: "compose", directoryHint: .isDirectory)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let dest = dir.appending(path: UUID().uuidString + "." + (received.file.pathExtension.isEmpty ? "mov" : received.file.pathExtension))
            try FileManager.default.copyItem(at: received.file, to: dest)
            return VideoFile(url: dest)
        }
    }
}

enum MediaExporter {
    struct Result: Sendable { let url: URL; let poster: Data; let width: Int; let height: Int; let durationMs: Int }
    enum ExportError: Error { case incompatible, failed(String), tooLarge }

    /// Exports to an H.264 MP4 (≤ 1080p, ≤ 60 s, moov atom first) and grabs a poster frame.
    nonisolated static func exportMP4(from source: URL, maxSeconds: Double = 60) async throws -> Result {
        let asset = AVURLAsset(url: source)
        let duration = try await asset.load(.duration)
        let seconds = min(CMTimeGetSeconds(duration), maxSeconds)
        let range = CMTimeRange(start: .zero, duration: CMTime(seconds: seconds, preferredTimescale: 600))

        let presets = [AVAssetExportPreset1920x1080, AVAssetExportPreset1280x720, AVAssetExportPresetMediumQuality]
        var chosen: String?
        for p in presets where await AVAssetExportSession.compatibility(ofExportPreset: p, with: asset, outputFileType: .mp4) { chosen = p; break }
        guard let preset = chosen, let session = AVAssetExportSession(asset: asset, presetName: preset) else { throw ExportError.incompatible }
        let out = FileManager.default.temporaryDirectory.appending(path: "compose/\(UUID().uuidString).mp4")
        try? FileManager.default.createDirectory(at: out.deletingLastPathComponent(), withIntermediateDirectories: true)
        session.outputURL = out
        session.outputFileType = .mp4
        session.shouldOptimizeForNetworkUse = true
        session.timeRange = range
        if #available(iOS 18, *) {
            try await session.export(to: out, as: .mp4)
        } else {
            nonisolated(unsafe) let s = session
            try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
                s.exportAsynchronously {
                    if s.status == .completed { c.resume() } else { c.resume(throwing: ExportError.failed(s.error?.localizedDescription ?? "export failed")) }
                }
            }
        }
        let size = (try? FileManager.default.attributesOfItem(atPath: out.path)[.size] as? Int) ?? 0
        if size > 250 * 1024 * 1024 { throw ExportError.tooLarge }

        let exported = AVURLAsset(url: out)
        let gen = AVAssetImageGenerator(asset: exported)
        gen.appliesPreferredTrackTransform = true
        gen.maximumSize = CGSize(width: 1440, height: 1440)
        let (cg, _) = try await gen.image(at: CMTime(seconds: min(0.5, seconds / 2), preferredTimescale: 600))
        let poster = UIImage(cgImage: cg).jpegData(compressionQuality: 0.85) ?? Data()
        return Result(url: out, poster: poster, width: cg.width, height: cg.height, durationMs: Int(seconds * 1000))
    }
}
