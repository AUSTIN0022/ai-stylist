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

    /// The sticker for an item, built when missing or older than its source. Source: the product photo (cut out with `cutout`),
    /// else the saved cut-out. nil when there is neither (or the product photo has no clear subject): callers show the plain image.
    public static func image(for id: UUID, store: ImageStore, cutout: CutoutProviding, maxPixel: Int) async -> CGImage? {
        let sticker = store.url(for: ImageStore.stickerName, id: id)
        let product = store.url(for: ImageStore.productName, id: id), cut = store.url(for: ImageStore.cutoutName, id: id)
        let fm = FileManager.default
        let source = fm.fileExists(atPath: product.path) ? product : fm.fileExists(atPath: cut.path) ? cut : nil
        guard let source, let sourceDate = modified(source) else { return nil }
        if let d = modified(sticker), d >= sourceDate, let img = ImageCodec.thumbnail(at: sticker, maxPixel: maxPixel) { return img }
        guard let full = ImageCodec.thumbnail(at: source, maxPixel: 1200) else { return nil }
        let base: CGImage
        if source == product {
            guard let r = try? await cutout.cutout(from: full) else { return nil }
            base = r.cutout
        } else { base = full }
        guard let made = outlined(base), let png = ImageCodec.pngData(made) else { return nil }
        try? store.save(png, named: ImageStore.stickerName, for: id)
        return ImageCodec.thumbnail(at: sticker, maxPixel: maxPixel) ?? made
    }
}
