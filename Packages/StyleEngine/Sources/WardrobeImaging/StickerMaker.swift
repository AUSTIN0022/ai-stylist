import CoreGraphics
import Foundation

/// The outfit "sticker": a garment trimmed to its edges with a thin white outline, like a cut-out sticker.
/// Derived from the product photo (cut out with Vision) or, when there is none, from the saved cut-out; cached as `sticker.png`.
public enum StickerMaker {
    public static let outlineWidth = 6

    private static func rgba(_ image: CGImage) -> (data: [UInt8], ctx: CGContext)? {
        let w = image.width, h = image.height
        guard w > 0, h > 0, let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        var data = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(data: &data, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: space,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return (data, ctx)
    }

    /// Trims transparent margins and adds a white outline `width` px thick. nil when nothing is opaque.
    public static func outlined(_ image: CGImage, width r: Int = outlineWidth) -> CGImage? {
        guard let (data, _) = rgba(image) else { return nil }
        let w = image.width, h = image.height
        var minX = w, minY = h, maxX = -1, maxY = -1
        for y in 0..<h { for x in 0..<w where data[(y * w + x) * 4 + 3] > 16 {
            minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
        } }
        guard maxX >= minX, let crop = image.cropping(to: CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)),
              let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        let cw = crop.width, ch = crop.height, ow = cw + 2 * r, oh = ch + 2 * r
        func context(_ w: Int, _ h: Int) -> CGContext? {
            CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        }
        // White silhouette of the garment: the garment drawn, then everything opaque turned white.
        guard let sil = context(cw, ch) else { return nil }
        let box = CGRect(x: 0, y: 0, width: cw, height: ch)
        sil.draw(crop, in: box)
        sil.setBlendMode(.sourceIn); sil.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1)); sil.fill(box)
        guard let white = sil.makeImage(), let out = context(ow, oh) else { return nil }
        // Stamp the silhouette around a disc of radius r (rings, so the outline is solid and round), then the garment on top.
        for ring in stride(from: 1.0, through: Double(r), by: 1.0) {
            let steps = max(12, Int(ring * 8))
            for k in 0..<steps {
                let a = 2 * Double.pi * Double(k) / Double(steps)
                out.draw(white, in: box.offsetBy(dx: Double(r) + ring * cos(a), dy: Double(r) + ring * sin(a)))
            }
        }
        out.draw(white, in: box.offsetBy(dx: Double(r), dy: Double(r)))
        out.draw(crop, in: box.offsetBy(dx: Double(r), dy: Double(r)))
        return out.makeImage()
    }

    private static func modified(_ url: URL) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
    }

    /// Decoded stickers, so reopening a card or the builder costs no disk read. Keyed by file, modification time and size.
    private nonisolated(unsafe) static let memory = NSCache<NSString, CGImage>()
    /// One cut-out at a time, one job per item (see `StickerGate`).
    private static let gate = StickerGate()

    private enum Quick { case hit(CGImage), skip, miss }

    private static func source(for id: UUID, store: ImageStore) -> (url: URL, date: Date, isProduct: Bool)? {
        let fm = FileManager.default
        let product = store.url(for: ImageStore.productName, id: id), cut = store.url(for: ImageStore.cutoutName, id: id)
        if fm.fileExists(atPath: product.path), let d = modified(product) { return (product, d, true) }
        if fm.fileExists(atPath: cut.path), let d = modified(cut) { return (cut, d, false) }
        return nil
    }

    /// Everything that needs no cut-out: a fresh sticker file (via memory), or a fresh "no clear subject" marker.
    private static func quick(_ id: UUID, _ store: ImageStore, _ maxPixel: Int) -> Quick {
        guard let src = source(for: id, store: store) else { return .miss }
        let sticker = store.url(for: ImageStore.stickerName, id: id)
        if let d = modified(sticker), d >= src.date, let img = decodeCaching(sticker, modified: d, maxPixel) { return .hit(img) }
        if let d = modified(store.url(for: ImageStore.stickerSkipName, id: id)), d >= src.date { return .skip }
        return .miss
    }

    /// The sticker for an item. Source: the product photo (cut out with `cutout`), else the saved cut-out. Built when missing or older
    /// than its source, one at a time, once per item. nil when there is no source, or the product photo has no clear subject (that is
    /// remembered until the photo changes): callers then show the plain image. Never runs its work on the caller's actor.
    public static func image(for id: UUID, store: ImageStore, cutout: CutoutProviding, maxPixel: Int) async -> CGImage? {
        switch await Task.detached(priority: .userInitiated, operation: { quick(id, store, maxPixel) }).value {
        case .hit(let img): return img
        case .skip: return nil
        case .miss: return await gate.build(id: id, store: store, cutout: cutout, maxPixel: maxPixel)
        }
    }

    /// Builds the missing stickers in the background, one after another (call at launch, at low priority).
    public static func prewarm(ids: [UUID], store: ImageStore, cutout: CutoutProviding) async {
        for id in ids { _ = await image(for: id, store: store, cutout: cutout, maxPixel: 200) }
    }

    fileprivate static func make(_ id: UUID, _ store: ImageStore, _ cutout: CutoutProviding, _ maxPixel: Int) async -> CGImage? {
        guard let src = source(for: id, store: store), let full = ImageCodec.thumbnail(at: src.url, maxPixel: 1200) else { return nil }
        let sticker = store.url(for: ImageStore.stickerName, id: id), skip = store.url(for: ImageStore.stickerSkipName, id: id)
        let base: CGImage
        if src.isProduct {
            guard let r = try? await cutout.cutout(from: full) else {
                try? store.save(Data(), named: ImageStore.stickerSkipName, for: id)      // remember: do not retry until the photo changes
                return nil
            }
            base = r.cutout
        } else { base = full }
        guard let made = outlined(base), let png = ImageCodec.pngData(made) else { return nil }
        try? store.save(png, named: ImageStore.stickerName, for: id)
        try? FileManager.default.removeItem(at: skip)
        return modified(sticker).flatMap { decodeCaching(sticker, modified: $0, maxPixel) } ?? made
    }

    /// The sticker file decoded at `maxPixel`, from memory when it was decoded before (same file, same time, same size).
    private static func decodeCaching(_ url: URL, modified d: Date, _ maxPixel: Int) -> CGImage? {
        let key = "\(url.path)|\(d.timeIntervalSince1970)|\(maxPixel)" as NSString
        if let img = memory.object(forKey: key) { return img }
        guard let img = ImageCodec.thumbnail(at: url, maxPixel: maxPixel) else { return nil }
        memory.setObject(img, forKey: key)
        return img
    }
}

/// Runs sticker builds one at a time (a Vision cut-out is heavy) and once per item however many views ask.
private actor StickerGate {
    private var inflight: [UUID: Task<CGImage?, Never>] = [:]
    private var tail: Task<Void, Never>?

    func build(id: UUID, store: ImageStore, cutout: CutoutProviding, maxPixel: Int) async -> CGImage? {
        if let running = inflight[id] { return await running.value }
        let prior = tail
        let job = Task<CGImage?, Never> { await prior?.value; return await StickerMaker.make(id, store, cutout, maxPixel) }
        inflight[id] = job
        tail = Task { _ = await job.value }
        let result = await job.value
        inflight[id] = nil
        return result
    }
}
