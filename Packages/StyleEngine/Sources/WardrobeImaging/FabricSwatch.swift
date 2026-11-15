import CoreGraphics
import Foundation

/// A square patch of plain fabric cut from the cut-out, sent to Image Playground as a colour and texture reference.
/// Fully inside the garment (at least 8% of its short side from any edge or hole) and the most uniform such area,
/// so it shows cloth, not a logo, print or seam. Pure pixels; the Mac tests cover it.
public enum FabricSwatch {
    public static let side = 512
    static let analysisSide = 160, edgeMargin = 0.08, minPatch = 32
    static let fractions = [0.30, 0.22, 0.16, 0.12]

    /// 512x512 opaque patch, or nil when the garment is too small or thin for a clean square (the flow then goes on without it).
    public static func crop(_ cutout: CGImage) -> CGImage? {
        let p = PixelBuffer(cutout, maxSide: analysisSide)
        let w = p.width, h = p.height
        var x0 = w, y0 = h, x1 = -1, y1 = -1
        var opaque = [Int](repeating: 0, count: (w + 1) * (h + 1)), lum = [Double](repeating: 0, count: (w + 1) * (h + 1)), lum2 = lum
        for y in 0..<h { for x in 0..<w {
            let i = (y * w + x) * 4, o = p.data[i + 3] >= 250
            if o {
                x0 = min(x0, x); x1 = max(x1, x); y0 = min(y0, y); y1 = max(y1, y)
            }
            let l = o ? (0.299 * Double(p.data[i]) + 0.587 * Double(p.data[i + 1]) + 0.114 * Double(p.data[i + 2])) : 0
            let a = (y + 1) * (w + 1) + x + 1
            opaque[a] = (o ? 1 : 0) + opaque[a - 1] + opaque[a - (w + 1)] - opaque[a - (w + 2)]
            lum[a] = l + lum[a - 1] + lum[a - (w + 1)] - lum[a - (w + 2)]
            lum2[a] = l * l + lum2[a - 1] + lum2[a - (w + 1)] - lum2[a - (w + 2)]
        } }
        guard x1 >= 0 else { return nil }
        func sum<T: AdditiveArithmetic>(_ t: [T], _ x: Int, _ y: Int, _ s: Int) -> T {
            t[(y + s) * (w + 1) + x + s] - t[y * (w + 1) + x + s] - t[(y + s) * (w + 1) + x] + t[y * (w + 1) + x]
        }
        let scale = Double(cutout.width) / Double(w)
        let short = min(x1 - x0 + 1, y1 - y0 + 1), m = Int((edgeMargin * Double(short)).rounded(.up))
        let cx = Double(x0 + x1) / 2, cy = Double(y0 + y1) / 2
        for f in fractions {
            let s = Int(f * Double(short))
            guard Double(s) * scale >= Double(minPatch) else { continue }
            var best: (score: Double, x: Int, y: Int)?
            for y in stride(from: max(0, y0 + m), through: min(h - s, y1 - m - s + 1), by: 2) {
                for x in stride(from: max(0, x0 + m), through: min(w - s, x1 - m - s + 1), by: 2) {
                    let ex = x - m, ey = y - m, es = s + 2 * m
                    guard ex >= 0, ey >= 0, ex + es <= w, ey + es <= h, sum(opaque, ex, ey, es) == es * es else { continue }
                    let n = Double(s * s), mean = sum(lum, x, y, s) / n
                    let variance = sum(lum2, x, y, s) / n - mean * mean
                    let d = (Double(x) + Double(s) / 2 - cx) * (Double(x) + Double(s) / 2 - cx) + (Double(y) + Double(s) / 2 - cy) * (Double(y) + Double(s) / 2 - cy)
                    let score = variance + 1e-6 * d   // ties go to the middle of the garment
                    if best == nil || score < best!.score { best = (score, x, y) }
                }
            }
            guard let b = best else { continue }
            let rect = CGRect(x: (Double(b.x) * scale).rounded(), y: (Double(b.y) * scale).rounded(),
                              width: (Double(s) * scale).rounded(), height: (Double(s) * scale).rounded())
                .intersection(CGRect(x: 0, y: 0, width: cutout.width, height: cutout.height))
            guard let patch = cutout.cropping(to: rect),
                  let ctx = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0, space: sRGBSpace,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
            ctx.interpolationQuality = .high
            ctx.draw(patch, in: CGRect(x: 0, y: 0, width: side, height: side))
            return ctx.makeImage()
        }
        return nil
    }

    /// Writes fabric.jpg from the item's cut-out. False (and no file) when there is no cut-out or no clean patch.
    @discardableResult
    public static func save(for id: UUID, store: ImageStore) -> Bool {
        let old = store.url(for: ImageStore.fabricName, id: id)
        guard let data = try? store.load(ImageStore.cutoutName, for: id), let cut = ImageCodec.decode(data),
              let patch = crop(cut), let jpeg = ImageCodec.jpegData(patch, quality: 0.92),
              (try? store.save(jpeg, named: ImageStore.fabricName, for: id)) != nil else {
            try? FileManager.default.removeItem(at: old)   // a stale patch from an earlier cut-out must not outlive it
            return false
        }
        return true
    }
}
