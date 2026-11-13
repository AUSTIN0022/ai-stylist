import CoreGraphics

public struct CutoutCandidate: Sendable, Equatable {
    public let index: Int
    /// Normalised to the image, top-left origin.
    public let bounds: CGRect
    /// Instance area / image area.
    public let areaShare: Double
    public let score: Double
    public init(index: Int, bounds: CGRect, areaShare: Double, score: Double) { self.index = index; self.bounds = bounds; self.areaShare = areaShare; self.score = score }
}

/// Which Vision instance is the garment. Pure logic on masks, so it runs on the Mac with synthetic masks.
public enum SubjectSelector {
    public static let boxHint = "Put the item inside the box"

    public struct Selection: Sendable, Equatable {
        public var candidates: [CutoutCandidate]
        public var chosen: [Int]
        public var needsChoice: Bool
        public var noClearItem: Bool
    }

    /// Score = position (overlap with the box, else closeness to the centre) + 1.5 x area share - 1 if it touches 2+ frame edges.
    public static func select(_ instances: [Mask], box: CGRect?) -> Selection {
        var candidates: [CutoutCandidate] = [], eligible: [CutoutCandidate] = []
        for (i, m) in instances.enumerated() {
            guard let b = m.bounds else { continue }
            let w = Double(m.width), h = Double(m.height)
            let nb = CGRect(x: b.minX / w, y: b.minY / h, width: b.width / w, height: b.height / h)
            let share = Double(m.foregroundCount) / (w * h)
            let position: Double
            if let box {
                var inside = 0
                for y in 0..<m.height { for x in 0..<m.width where m.pixels[y * m.width + x] > 127 && box.contains(CGPoint(x: (Double(x) + 0.5) / w, y: (Double(y) + 0.5) / h)) { inside += 1 } }
                position = Double(inside) / Double(max(1, m.foregroundCount))
            } else {
                position = 1 - hypot(nb.midX - 0.5, nb.midY - 0.5) / hypot(0.5, 0.5)
            }
            let c = CutoutCandidate(index: i, bounds: nb, areaShare: share, score: position + 1.5 * share - (m.touchedEdges >= 2 ? 1 : 0))
            candidates.append(c)
            if box.map({ $0.contains(CGPoint(x: nb.midX, y: nb.midY)) }) ?? true { eligible.append(c) }
        }
        guard let best = eligible.min(by: { $0.score != $1.score ? $0.score > $1.score : $0.index < $1.index }) else {
            return Selection(candidates: candidates, chosen: [], needsChoice: false, noClearItem: true)
        }
        var chosen = [best.index]
        for c in eligible where c.index != best.index && isTwin(c, of: best) { chosen.append(c.index) }
        chosen = expand(chosen, in: instances)
        let rival = eligible.filter { !chosen.contains($0.index) }.max { $0.score < $1.score }
        let needsChoice = rival.map { best.score - $0.score <= 0.15 * abs(best.score) } ?? false
        return Selection(candidates: candidates, chosen: chosen, needsChoice: needsChoice, noClearItem: false)
    }

    /// Instance containing the point (the largest if several), else the nearest one. Normalised top-left point.
    public static func select(_ instances: [Mask], tap p: CGPoint) -> [Int] {
        var hit: (Int, Int)?   // index, area
        var nearest: (Int, Double)?
        for (i, m) in instances.enumerated() {
            guard let b = m.bounds else { continue }
            let x = min(m.width - 1, max(0, Int(p.x * Double(m.width)))), y = min(m.height - 1, max(0, Int(p.y * Double(m.height))))
            if m.pixels[y * m.width + x] > 127, m.foregroundCount > (hit?.1 ?? -1) { hit = (i, m.foregroundCount) }
            let px = p.x * Double(m.width), py = p.y * Double(m.height)
            let d = hypot(max(b.minX - px, 0, px - b.maxX), max(b.minY - py, 0, py - b.maxY))
            if d < (nearest?.1 ?? .infinity) { nearest = (i, d) }
        }
        guard let i = hit?.0 ?? nearest?.0 else { return [] }
        return expand([i], in: instances)
    }

    /// Adds instances lying fully inside a chosen instance's bounds (a print Vision split off the garment).
    public static func expand(_ chosen: [Int], in instances: [Mask]) -> [Int] {
        var out = Set(chosen)
        for c in chosen {
            guard instances.indices.contains(c), let cb = instances[c].bounds else { continue }
            for (i, m) in instances.enumerated() where !out.contains(i) {
                if let b = m.bounds, cb.contains(b) { out.insert(i) }
            }
        }
        return out.sorted()
    }

    /// Area within 50% of the best and boxes no further apart than one box-width (a pair of shoes).
    static func isTwin(_ c: CutoutCandidate, of best: CutoutCandidate) -> Bool {
        guard min(c.areaShare, best.areaShare) >= 0.5 * max(c.areaShare, best.areaShare) else { return false }
        let a = best.bounds, b = c.bounds
        let dx = max(0, max(a.minX, b.minX) - min(a.maxX, b.maxX)), dy = max(0, max(a.minY, b.minY) - min(a.maxY, b.maxY))
        return hypot(dx, dy) <= a.width
    }
}

public enum CameraBox {
    /// Screen-space guide rect in an aspect-fill preview -> normalised photo rect (top-left origin), clamped to the photo.
    public static func photoRect(forGuide guide: CGRect, preview: CGSize, photo: CGSize) -> CGRect {
        let scale = max(preview.width / photo.width, preview.height / photo.height)
        let shown = CGSize(width: photo.width * scale, height: photo.height * scale)
        let off = CGPoint(x: (preview.width - shown.width) / 2, y: (preview.height - shown.height) / 2)
        let r = CGRect(x: (guide.minX - off.x) / shown.width, y: (guide.minY - off.y) / shown.height,
                       width: guide.width / shown.width, height: guide.height / shown.height)
        return r.intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
    }
}
