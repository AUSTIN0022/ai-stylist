import CoreGraphics
import Foundation
import StyleEngine

public struct ExtractedColors: Sendable, Equatable {
    /// Up to 3 hex colours (no #), largest first.
    public var hexes: [String]
    /// One name per hex, or `[.multicolor]` when more than 3 colours are significant.
    public var names: [ColorName]
    /// One flag per name: the review step asks about these (near a boundary, or the black/white rule fired near its boundary).
    public var ambiguous: [Bool]
}

/// Colour from pixels, no AI: k-means (k = 4) in Lab on a 64 px copy of the cut-out.
public enum ColorExtractor {
    struct Lab { var l, a, b: Double
        func dist(_ o: Lab) -> Double { ((l - o.l) * (l - o.l) + (a - o.a) * (a - o.a) + (b - o.b) * (b - o.b)).squareRoot() }
    }

    static func lab(_ r: Double, _ g: Double, _ b: Double) -> Lab {   // r,g,b 0...255 sRGB
        func lin(_ c: Double) -> Double { let v = c / 255; return v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
        let (R, G, B) = (lin(r), lin(g), lin(b))
        let x = (0.4124 * R + 0.3576 * G + 0.1805 * B) / 0.95047
        let y = 0.2126 * R + 0.7152 * G + 0.0722 * B
        let z = (0.0193 * R + 0.1192 * G + 0.9505 * B) / 1.08883
        func f(_ t: Double) -> Double { t > 0.008856 ? cbrt(t) : 7.787 * t + 16.0 / 116 }
        return Lab(l: 116 * f(y) - 16, a: 500 * (f(x) - f(y)), b: 200 * (f(y) - f(z)))
    }

    private static let references: [(ColorName, Lab)] = ColorName.allCases.compactMap { n in
        guard let h = n.referenceHex, let v = UInt32(h, radix: 16) else { return nil }
        return (n, lab(Double((v >> 16) & 255), Double((v >> 8) & 255), Double(v & 255)))
    }

    /// Black / white rules first, then nearest reference in Lab. Ambiguous when a rule fired or the two
    /// nearest references are within 6 Lab units of each other (as distances from the colour).
    public static func classify(hex: String) -> (name: ColorName, ambiguous: Bool) {
        let v = UInt32(hex, radix: 16) ?? 0
        let c = lab(Double((v >> 16) & 255), Double((v >> 8) & 255), Double(v & 255))
        let chroma = (c.a * c.a + c.b * c.b).squareRoot()
        if c.l < 22, chroma < 12 { return (.black, c.l >= 12 || chroma >= 6) }   // ambiguous only near the boundary
        if c.l > 80, chroma < 6 { return (.white, c.l <= 90 || chroma >= 4) }   // indoor light reads white at L 84-86
        // A dark but coloured pixel (dark brown, dark green) is not charcoal.
        let d = references.filter { !(c.l < 30 && chroma >= 12 && $0.0 == .charcoal) }.map { ($0.0, $0.1.dist(c)) }.sorted { $0.1 < $1.1 }
        return (d[0].0, d[1].1 - d[0].1 < 6)
    }

    public static func name(forHex hex: String) -> ColorName { classify(hex: hex).name }

    static let minShare = 0.15, maxColors = 3, k = 4


    public static func extract(from cutout: CGImage) -> ExtractedColors {
        let buf = PixelBuffer(cutout, maxSide: 64)
        let opaque = Mask(width: buf.width, height: buf.height, pixels: (0..<buf.width * buf.height).map { buf.data[$0 * 4 + 3] >= 250 ? 255 : 0 })
        // Ignore the outer 2 px of the mask edge; tiny items fall back to every opaque pixel.
        var valid = opaque.eroded(by: 2, outsideIsForeground: false)
        if valid.foregroundCount == 0 { valid = opaque }

        var rgbs: [(Double, Double, Double)] = [], labs: [Lab] = []
        for i in 0..<valid.pixels.count where valid.pixels[i] > 127 {
            let r = Double(buf.data[i * 4]), g = Double(buf.data[i * 4 + 1]), b = Double(buf.data[i * 4 + 2])
            rgbs.append((r, g, b)); labs.append(lab(r, g, b))
        }
        guard !labs.isEmpty else { return ExtractedColors(hexes: [], names: [], ambiguous: []) }

        // Farthest-first start (deterministic), then Lloyd iterations.
        var centers = [labs[0]]
        while centers.count < k {
            let far = labs.max { a, b in centers.map { a.dist($0) }.min()! < centers.map { b.dist($0) }.min()! }!
            centers.append(far)
        }
        var assign = [Int](repeating: 0, count: labs.count)
        for _ in 0..<10 {
            for (i, p) in labs.enumerated() { assign[i] = centers.indices.min { p.dist(centers[$0]) < p.dist(centers[$1]) }! }
            for c in centers.indices {
                let m = labs.indices.filter { assign[$0] == c }
                if m.isEmpty { continue }
                let n = Double(m.count)
                centers[c] = Lab(l: m.reduce(0) { $0 + labs[$1].l } / n, a: m.reduce(0) { $0 + labs[$1].a } / n, b: m.reduce(0) { $0 + labs[$1].b } / n)
            }
        }
        // Clusters: count, mean rgb, centre. Merge near-identical centres (one colour split in two).
        struct Cluster { var count: Int; var sum: (Double, Double, Double); var center: Lab }
        var clusters: [Cluster] = []
        for c in centers.indices {
            let m = labs.indices.filter { assign[$0] == c }
            if m.isEmpty { continue }
            let s = m.reduce((0.0, 0.0, 0.0)) { ($0.0 + rgbs[$1].0, $0.1 + rgbs[$1].1, $0.2 + rgbs[$1].2) }
            if let j = clusters.firstIndex(where: { $0.center.dist(centers[c]) < 8 }) {
                clusters[j].count += m.count
                clusters[j].sum = (clusters[j].sum.0 + s.0, clusters[j].sum.1 + s.1, clusters[j].sum.2 + s.2)
            } else { clusters.append(Cluster(count: m.count, sum: s, center: centers[c])) }
        }
        clusters.sort { $0.count > $1.count }
        let kept = clusters.filter { Double($0.count) / Double(labs.count) >= minShare }
        let hexes = (kept.isEmpty ? [clusters[0]] : kept).prefix(maxColors).map { c -> String in
            let n = Double(c.count)
            return String(format: "%02X%02X%02X", Int((c.sum.0 / n).rounded()), Int((c.sum.1 / n).rounded()), Int((c.sum.2 / n).rounded()))
        }
        if kept.count > maxColors { return ExtractedColors(hexes: Array(hexes), names: [.multicolor], ambiguous: [false]) }
        let cls = hexes.map { classify(hex: $0) }
        return ExtractedColors(hexes: Array(hexes), names: cls.map(\.name), ambiguous: cls.map(\.ambiguous))
    }
}
