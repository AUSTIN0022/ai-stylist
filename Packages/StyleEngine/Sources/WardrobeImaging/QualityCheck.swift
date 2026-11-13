import CoreGraphics

public typealias QualityReason = QualityVerdict

public enum QualityVerdict: String, Sendable, Equatable {
    case ok, tooDark, blurry, noClearItem, cutOff, busyBackground, lightOnLight

    /// Text for the user; nil when ok.
    public var message: String? {
        switch self {
        case .ok: nil
        case .tooDark: "Too dark"
        case .blurry: "Blurry"
        case .noClearItem: "No clear item"
        case .cutOff: "Item cut off"
        case .busyBackground: "Busy background. A plain sheet or the floor works better."
        case .lightOnLight: "Light item on a light surface. A dark sheet or floor gives a cleaner cut-out."
        }
    }
}

public struct QualityMeasurements: Sendable, Equatable {
    public var luminance: Double       // mean, 0...1
    public var sharpness: Double       // variance of a Laplacian on 0...255 grey, 256 px copy
    public var maskCoverage: Double?   // nil when there is no mask
    public var touchedEdges: Int
    /// Share of pixels with a strong edge around the item (its bounds grown 20%, mask excluded). 0 without a mask.
    public var busyEdgeDensity = 0.0
    /// Mean Lab L of the item, and of the area around it (bounds grown 20%, mask excluded). Nil without a mask.
    public var garmentLightness: Double?
    public var surroundLightness: Double?
}

/// Thresholds are first guesses; settle them from the 30 good + 10 bad photos (SPRINT_1_TESTS "Quality thresholds").
public struct QualityThresholds: Sendable {
    public var minLuminance = 0.15
    public var minSharpness = 25.0
    public var minCoverage = 0.08
    public var maxBusyEdgeDensity = 0.12
    public var minGarmentLightness = 75.0, minSurroundLightness = 70.0
    public init() {}
}

public enum QualityCheck {
    public static func measure(image: CGImage, mask: Mask?) -> QualityMeasurements {
        let buf = PixelBuffer(image, maxSide: 256)
        let w = buf.width, h = buf.height
        var grey = [Double](repeating: 0, count: w * h)
        for i in 0..<w * h {
            grey[i] = 0.2126 * Double(buf.data[i * 4]) + 0.7152 * Double(buf.data[i * 4 + 1]) + 0.0722 * Double(buf.data[i * 4 + 2])
        }
        let lum = grey.reduce(0, +) / Double(w * h) / 255

        // Blur is judged inside the mask only (plain fabric elsewhere has few edges); whole frame without one.
        let activeMask = mask.flatMap { $0.foregroundCount > 0 ? $0 : nil }
        func inside(_ x: Int, _ y: Int) -> Bool {
            guard let m = activeMask else { return true }
            return m.pixels[min(m.height - 1, y * m.height / h) * m.width + min(m.width - 1, x * m.width / w)] > 127
        }
        var vals: [Double] = []
        if w > 2, h > 2 {
            for y in 1..<(h - 1) { for x in 1..<(w - 1) where inside(x, y) {
                vals.append(4 * grey[y * w + x] - grey[y * w + x - 1] - grey[y * w + x + 1] - grey[(y - 1) * w + x] - grey[(y + 1) * w + x])
            } }
        }
        if vals.count < 50, mask != nil { return measure(image: image, mask: nil).with(coverage: mask?.coverage, edges: mask?.touchedEdges ?? 0) }
        let mean = vals.reduce(0, +) / Double(max(1, vals.count))
        let variance = vals.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(max(1, vals.count))
        let light = activeMask.flatMap { lightness(buf: buf, mask: $0) }
        return QualityMeasurements(luminance: lum, sharpness: variance, maskCoverage: mask?.coverage, touchedEdges: mask?.touchedEdges ?? 0,
                                   busyEdgeDensity: activeMask.map { busyDensity(grey: grey, w: w, h: h, mask: $0) } ?? 0,
                                   garmentLightness: light?.0, surroundLightness: light?.1)
    }

    /// Mean Lab L inside the mask and in the grown bounds outside it. ponytail: mean, not the dominant colour; fine for a hint.
    static func lightness(buf: PixelBuffer, mask: Mask) -> (Double, Double)? {
        guard let b = mask.bounds else { return nil }
        let w = buf.width, h = buf.height
        let gx = b.width * 0.2, gy = b.height * 0.2
        let x0 = max(0, Int((b.minX - gx) * Double(w) / Double(mask.width))), x1 = min(w, Int((b.maxX + gx) * Double(w) / Double(mask.width)) + 1)
        let y0 = max(0, Int((b.minY - gy) * Double(h) / Double(mask.height))), y1 = min(h, Int((b.maxY + gy) * Double(h) / Double(mask.height)) + 1)
        var inSum = 0.0, inN = 0, outSum = 0.0, outN = 0
        for y in y0..<y1 { for x in x0..<x1 {
            let i = (y * w + x) * 4
            let l = ColorExtractor.lab(Double(buf.data[i]), Double(buf.data[i + 1]), Double(buf.data[i + 2])).l
            if mask.pixels[min(mask.height - 1, y * mask.height / h) * mask.width + min(mask.width - 1, x * mask.width / w)] > 127 { inSum += l; inN += 1 }
            else { outSum += l; outN += 1 }
        } }
        return inN > 0 && outN > 0 ? (inSum / Double(inN), outSum / Double(outN)) : nil
    }

    /// Edge density outside the mask (a 2 px skirt around it is skipped, so the item's own outline does not count),
    /// inside the mask bounds grown 20%.
    static func busyDensity(grey: [Double], w: Int, h: Int, mask: Mask) -> Double {
        guard let b = mask.bounds, w > 2, h > 2 else { return 0 }
        let gx = b.width * 0.2, gy = b.height * 0.2
        let x0 = max(1, Int((b.minX - gx) * Double(w) / Double(mask.width))), x1 = min(w - 1, Int((b.maxX + gx) * Double(w) / Double(mask.width)))
        let y0 = max(1, Int((b.minY - gy) * Double(h) / Double(mask.height))), y1 = min(h - 1, Int((b.maxY + gy) * Double(h) / Double(mask.height)))
        let skirt = 2
        func maskAt(_ x: Int, _ y: Int) -> Bool {
            mask.pixels[min(mask.height - 1, max(0, y * mask.height / h)) * mask.width + min(mask.width - 1, max(0, x * mask.width / w))] > 127
        }
        var total = 0, edges = 0
        if x0 < x1, y0 < y1 {
            for y in y0..<y1 { for x in x0..<x1 {
                var near = false
                for dy in -skirt...skirt where !near { for dx in -skirt...skirt where maskAt(min(w - 1, max(0, x + dx)), min(h - 1, max(0, y + dy))) { near = true; break } }
                if near { continue }
                total += 1
                let lap = 4 * grey[y * w + x] - grey[y * w + x - 1] - grey[y * w + x + 1] - grey[(y - 1) * w + x] - grey[(y + 1) * w + x]
                if abs(lap) > 40 { edges += 1 }
            } }
        }
        return total < 50 ? 0 : Double(edges) / Double(total)
    }

    /// One reason, the first that applies: dark, blurry, no clear item, cut off, busy background, light on light (lowest priorities, never block).
    public static func decide(_ m: QualityMeasurements, _ t: QualityThresholds = QualityThresholds()) -> QualityVerdict {
        if m.luminance < t.minLuminance { return .tooDark }
        if m.sharpness < t.minSharpness { return .blurry }
        guard let cov = m.maskCoverage, cov >= t.minCoverage else { return .noClearItem }
        if m.touchedEdges >= 2 { return .cutOff }
        if m.busyEdgeDensity > t.maxBusyEdgeDensity { return .busyBackground }
        if let g = m.garmentLightness, let s = m.surroundLightness, g > t.minGarmentLightness, s > t.minSurroundLightness { return .lightOnLight }
        return .ok
    }

    /// Blur check on a region (normalised, top-left origin; nil = whole image), same Laplacian measure as `measure`.
    public static func isBlurry(_ image: CGImage, region: CGRect? = nil, thresholds: QualityThresholds = QualityThresholds()) -> Bool {
        var img = image
        if let r = region {
            let w = Double(image.width), h = Double(image.height)
            let rect = CGRect(x: r.minX * w, y: r.minY * h, width: r.width * w, height: r.height * h).integral
                .intersection(CGRect(x: 0, y: 0, width: w, height: h))
            if !rect.isEmpty, let c = image.cropping(to: rect) { img = c }
        }
        return measure(image: img, mask: nil).sharpness < thresholds.minSharpness
    }

    public static func check(image: CGImage, mask: Mask?, thresholds: QualityThresholds = QualityThresholds()) -> QualityVerdict {
        decide(measure(image: image, mask: mask), thresholds)
    }
}

private extension QualityMeasurements {
    func with(coverage: Double?, edges: Int) -> QualityMeasurements {
        var m = self; m.maskCoverage = coverage; m.touchedEdges = edges; return m
    }
}
