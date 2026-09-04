import Foundation
import Observation
import PhotosUI
import SwiftUI

@MainActor
@Observable
final class ComposeViewModel {
    enum Step: Equatable { case account, pick, preparing, edit, publishing, done }

    private let env: AppEnvironment
    var step: Step = .pick
    var draft = ComposeDraft()
    var pickerItems: [PhotosPickerItem] = []
    var progress: Double = 0
    var error: String?
    var newProductURL = ""
    var handle = ""
    var displayName = ""
    private(set) var published: Post?
    let styleOptions = ["minimalist", "old_money", "streetwear", "athleisure", "workwear", "scandi", "model_off_duty", "gorpcore", "coastal", "cottagecore", "y2k", "preppy", "glam", "vintage", "boho", "grunge", "coquette", "western"]

    init(environment: AppEnvironment) {
        self.env = environment
        if !environment.usingFixtures, environment.me?.primaryAuthor == nil { step = .account }
        if ProcessInfo.processInfo.arguments.contains("-seed-compose") { seedForTesting() }
    }

    /// UI tests cannot drive the system photo picker; this seeds a draft with a generated image.
    private func seedForTesting() {
        let size = CGSize(width: 720, height: 960)
        let img = UIGraphicsImageRenderer(size: size).image { ctx in
            UIColor(red: 0.85, green: 0.6, blue: 0.4, alpha: 1).setFill(); ctx.fill(CGRect(origin: .zero, size: size))
        }
        guard let data = img.jpegData(compressionQuality: 0.8), let (jpeg, w, h) = ImageResizer.jpeg(from: data, maxPixel: 1440) else { return }
        var m = ComposeMediaItem(kind: .image, width: w, height: h)
        m.jpeg = jpeg; m.thumb = ImageResizer.jpeg(from: jpeg, maxPixel: 400)?.0; m.preview = img
        draft.media = [m]
        step = .edit
    }

    var author: Author? { env.me?.primaryAuthor ?? (env.usingFixtures ? Author(id: UUID(), handle: "you", displayName: "You", kind: .creator) : nil) }

    func createAuthor() async {
        let h = handle.lowercased().trimmingCharacters(in: .whitespaces)
        guard h.range(of: "^[a-z0-9_.]{2,30}$", options: .regularExpression) != nil else { error = "Handle: 2–30 letters, numbers, dots or underscores"; return }
        do {
            _ = try await env.profileRepository.createCreatorAuthor(handle: h, displayName: displayName.isEmpty ? h : displayName)
            await env.refreshMe()
            error = nil
            step = .pick
        } catch { self.error = error.localizedDescription }
    }

    /// Runs when the picker selection changes: downsample images, export video.
    func prepareSelection() async {
        guard !pickerItems.isEmpty else { return }
        step = .preparing
        var items: [ComposeMediaItem] = []
        for item in pickerItems {
            let isVideo = item.supportedContentTypes.contains { $0.conforms(to: .movie) }
            do {
                if isVideo {
                    guard let file = try await item.loadTransferable(type: VideoFile.self) else { continue }
                    let r = try await MediaExporter.exportMP4(from: file.url)
                    var m = ComposeMediaItem(kind: .video, width: r.width, height: r.height)
                    m.videoURL = r.url; m.poster = r.poster; m.durationMs = r.durationMs; m.preview = UIImage(data: r.poster)
                    items = [m] // one video per post
                    break
                } else if let data = try await item.loadTransferable(type: Data.self) {
                    let processed = await Task.detached(priority: .userInitiated) { () -> (Data, Int, Int, Data?)? in
                        guard let (jpeg, w, h) = ImageResizer.jpeg(from: data, maxPixel: 1440) else { return nil }
                        let thumb = ImageResizer.jpeg(from: jpeg, maxPixel: 400, quality: 0.8)?.0
                        return (jpeg, w, h, thumb)
                    }.value
                    guard let (jpeg, w, h, thumb) = processed else { continue }
                    var m = ComposeMediaItem(kind: .image, width: w, height: h)
                    m.jpeg = jpeg; m.thumb = thumb; m.preview = UIImage(data: thumb ?? jpeg)
                    items.append(m)
                }
            } catch {
                self.error = error.localizedDescription
            }
        }
        draft.media = items
        step = items.isEmpty ? .pick : .edit
    }

    func removeMedia(_ id: UUID) {
        draft.media.removeAll { $0.id == id }
        if draft.media.isEmpty { pickerItems = []; step = .pick }
    }

    func addProductURL() {
        var raw = newProductURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if !raw.hasPrefix("http") { raw = "https://" + raw }
        guard let url = URL(string: raw), url.host() != nil else { error = "That doesn't look like a link"; return }
        guard !draft.products.contains(where: { $0.url == raw }) else { newProductURL = ""; return }
        guard draft.products.count < 10 else { error = "Up to 10 products per post"; return }
        error = nil
        newProductURL = ""
        var d = ProductDraft(url: raw)
        d.merchant = url.host()?.replacingOccurrences(of: "www.", with: "") ?? ""
        draft.products.append(d)
        let id = d.id
        Task {
            do {
                let s = try await env.scrapeRepository.scrape(url: raw)
                guard let i = draft.products.firstIndex(where: { $0.id == id }) else { return }
                draft.products[i].title = s.title ?? ""
                draft.products[i].imageUrl = s.imageUrl
                draft.products[i].priceCents = s.priceCents
                draft.products[i].currency = s.currency ?? "USD"
                draft.products[i].merchant = s.merchant ?? draft.products[i].merchant
                draft.products[i].brand = s.brand
                if let c = s.canonicalUrl { draft.products[i].url = c }
                draft.products[i].status = (s.ok ?? false) && !(s.title ?? "").isEmpty ? .ready : .manual
            } catch {
                guard let i = draft.products.firstIndex(where: { $0.id == id }) else { return }
                draft.products[i].status = .manual
            }
        }
    }

    func removeProduct(_ id: UUID) { draft.products.removeAll { $0.id == id } }

    func toggleStyle(_ tag: String) {
        if let i = draft.styleTags.firstIndex(of: tag) { draft.styleTags.remove(at: i) } else if draft.styleTags.count < 6 { draft.styleTags.append(tag) }
    }

    func publish() async {
        guard let author, draft.canPublish else { return }
        step = .publishing; progress = 0; error = nil
        do {
            let post = try await env.composerRepository.publish(draft, author: author) { p in Task { @MainActor in self.progress = p } }
            published = post
            step = .done
        } catch {
            self.error = error.localizedDescription
            step = .edit
        }
    }
}
