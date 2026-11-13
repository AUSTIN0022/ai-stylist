import CoreGraphics

/// The Adjust sheet's selection box, normalised to the photo (top-left origin). Pure, so it is tested on the Mac.
public struct SelectionBox: Equatable, Sendable {
    public static let minSide: CGFloat = 0.08
    public enum Corner: CaseIterable, Sendable { case topLeft, topRight, bottomLeft, bottomRight }
    public private(set) var rect: CGRect

    /// Clamped to the unit square, each side at least `minSide`.
    public init(_ r: CGRect) {
        let w = min(1, max(Self.minSide, r.width)), h = min(1, max(Self.minSide, r.height))
        rect = CGRect(x: min(max(0, r.minX), 1 - w), y: min(max(0, r.minY), 1 - h), width: w, height: h)
    }

    public func point(_ c: Corner) -> CGPoint {
        CGPoint(x: c == .topLeft || c == .bottomLeft ? rect.minX : rect.maxX, y: c == .topLeft || c == .topRight ? rect.minY : rect.maxY)
    }

    /// Moves one corner to `p` (clamped to the photo); the opposite corner stays and the box cannot get thinner than `minSide`.
    public mutating func dragCorner(_ c: Corner, to p: CGPoint) {
        let x = min(1, max(0, p.x)), y = min(1, max(0, p.y)), m = Self.minSide
        var (x0, x1, y0, y1) = (rect.minX, rect.maxX, rect.minY, rect.maxY)
        if c == .topLeft || c == .bottomLeft { x0 = min(x, x1 - m) } else { x1 = max(x, x0 + m) }
        if c == .topLeft || c == .topRight { y0 = min(y, y1 - m) } else { y1 = max(y, y0 + m) }
        rect = CGRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
    }

    /// Moves the whole box, keeping its size and staying inside the photo.
    public mutating func dragCentre(by d: CGSize) {
        rect.origin = CGPoint(x: min(max(0, rect.minX + d.width), 1 - rect.width), y: min(max(0, rect.minY + d.height), 1 - rect.height))
    }
}

/// Zoom and pan of the photo in its container. The photo is drawn at `fit` (its 1x rect inside the container), scaled
/// about the container centre, then shifted by `pan`. Maps view points to normalised photo points and back.
public struct PhotoViewport: Equatable, Sendable {
    public static let scaleRange: ClosedRange<CGFloat> = 1...5
    public var container: CGSize
    public var fit: CGRect
    public private(set) var scale: CGFloat = 1
    public private(set) var pan: CGSize = .zero

    public init(container: CGSize, fit: CGRect) { self.container = container; self.fit = fit }

    private var centre: CGPoint { CGPoint(x: container.width / 2, y: container.height / 2) }

    public func viewPoint(forPhoto p: CGPoint) -> CGPoint {
        let b = CGPoint(x: fit.minX + p.x * fit.width, y: fit.minY + p.y * fit.height)
        return CGPoint(x: centre.x + (b.x - centre.x) * scale + pan.width, y: centre.y + (b.y - centre.y) * scale + pan.height)
    }
    public func photoPoint(forView v: CGPoint) -> CGPoint {
        let b = CGPoint(x: centre.x + (v.x - pan.width - centre.x) / scale, y: centre.y + (v.y - pan.height - centre.y) / scale)
        return CGPoint(x: (b.x - fit.minX) / fit.width, y: (b.y - fit.minY) / fit.height)
    }

    public mutating func setScale(_ s: CGFloat) {
        scale = min(Self.scaleRange.upperBound, max(Self.scaleRange.lowerBound, s))
        setPan(pan)
    }

    /// The photo keeps covering the container along an axis where it is larger; where it is smaller it stays centred. 1x never pans.
    public mutating func setPan(_ p: CGSize) {
        func axis(_ v: CGFloat, _ lo: CGFloat, _ len: CGFloat, _ c: CGFloat, _ box: CGFloat) -> CGFloat {
            let start = c + (lo - c) * scale, size = len * scale          // scaled photo edge before pan
            if size <= box { return box / 2 - (start + size / 2) }       // centred
            return min(-start, max(box - start - size, v))               // left edge <= 0, right edge >= box
        }
        pan = scale == 1 ? .zero : CGSize(width: axis(p.width, fit.minX, fit.width, centre.x, container.width),
                                          height: axis(p.height, fit.minY, fit.height, centre.y, container.height))
    }
}
