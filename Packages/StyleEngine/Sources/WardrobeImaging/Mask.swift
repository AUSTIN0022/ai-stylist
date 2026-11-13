import CoreGraphics
import CoreVideo

/// A subject mask: 255 = foreground, 0 = background. Row 0 = top. Pure data, so it is testable on the Mac.
public struct Mask: Sendable, Equatable {
    public let width: Int, height: Int
    public let pixels: [UInt8]

    public init(width: Int, height: Int, pixels: [UInt8]) {
        precondition(pixels.count == width * height)
        self.width = width; self.height = height; self.pixels = pixels
    }

    /// From a Vision mask buffer (OneComponent32Float or OneComponent8). Values above half count as foreground.
    init?(pixelBuffer pb: CVPixelBuffer) {
        CVPixelBufferLockBaseAddress(pb, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pb, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(pb) else { return nil }
        let w = CVPixelBufferGetWidth(pb), h = CVPixelBufferGetHeight(pb), stride = CVPixelBufferGetBytesPerRow(pb)
        let format = CVPixelBufferGetPixelFormatType(pb)
        var out = [UInt8](repeating: 0, count: w * h)
        for y in 0..<h {
            let row = base + y * stride
            if format == kCVPixelFormatType_OneComponent32Float {
                let f = row.assumingMemoryBound(to: Float.self)
                for x in 0..<w where f[x] > 0.5 { out[y * w + x] = 255 }
            } else if format == kCVPixelFormatType_OneComponent8 {
                let b = row.assumingMemoryBound(to: UInt8.self)
                for x in 0..<w where b[x] > 127 { out[y * w + x] = 255 }
            } else { return nil }
        }
        self.init(width: w, height: h, pixels: out)
    }

    public var foregroundCount: Int { pixels.reduce(0) { $0 + ($1 > 127 ? 1 : 0) } }
    public var coverage: Double { Double(foregroundCount) / Double(max(1, width * height)) }

    /// Bounding box of the foreground in pixels, or nil when empty.
    public var bounds: CGRect? {
        var minX = width, minY = height, maxX = -1, maxY = -1
        for y in 0..<height { for x in 0..<width where pixels[y * width + x] > 127 {
            minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
        } }
        return maxX < 0 ? nil : CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
    }

    /// How many of the four frame edges the foreground touches (a few stray pixels do not count).
    public var touchedEdges: Int {
        func touches(_ coords: [(Int, Int)]) -> Bool {
            coords.reduce(0) { $0 + (pixels[$1.1 * width + $1.0] > 127 ? 1 : 0) } >= max(2, coords.count / 50)
        }
        let top = (0..<width).map { ($0, 0) }, bottom = (0..<width).map { ($0, height - 1) }
        let left = (0..<height).map { (0, $0) }, right = (0..<height).map { (width - 1, $0) }
        return [top, bottom, left, right].filter(touches).count
    }

    /// Union of same-sized masks (a pair of shoes is two instances). Nil for an empty list or mixed sizes.
    public static func union(_ masks: [Mask]) -> Mask? {
        guard let first = masks.first, masks.allSatisfy({ $0.width == first.width && $0.height == first.height }) else { return nil }
        var out = first.pixels
        for m in masks.dropFirst() { for i in out.indices where m.pixels[i] > 127 { out[i] = 255 } }
        return Mask(width: first.width, height: first.height, pixels: out)
    }

    /// Shrinks the foreground by `r` pixels on every side (removes soft-edge halos).
    /// `outsideIsForeground`: whether the frame border itself counts as foreground (an item cut off by the frame).
    public func eroded(by r: Int, outsideIsForeground: Bool = true) -> Mask {
        guard r > 0 else { return self }
        let outside: UInt8 = outsideIsForeground ? 255 : 0
        var h = pixels
        for y in 0..<height { for x in 0..<width {
            var v: UInt8 = 255
            for dx in -r...r { let xx = x + dx; if (xx < 0 || xx >= width ? outside : pixels[y * width + xx]) < 128 { v = 0; break } }
            h[y * width + x] = v
        } }
        var out = h
        for y in 0..<height { for x in 0..<width {
            var v: UInt8 = 255
            for dy in -r...r { let yy = y + dy; if (yy < 0 || yy >= height ? outside : h[yy * width + x]) < 128 { v = 0; break } }
            out[y * width + x] = v
        } }
        return Mask(width: width, height: height, pixels: out)
    }

    /// Nearest-neighbour downscale so the longer side is at most `maxSide`.
    public func resized(maxSide: Int) -> Mask {
        guard max(width, height) > maxSide else { return self }
        let s = Double(maxSide) / Double(max(width, height))
        let w = max(1, Int(Double(width) * s)), h = max(1, Int(Double(height) * s))
        var out = [UInt8](repeating: 0, count: w * h)
        for y in 0..<h { for x in 0..<w { out[y * w + x] = pixels[min(height - 1, Int(Double(y) / s)) * width + min(width - 1, Int(Double(x) / s))] } }
        return Mask(width: w, height: h, pixels: out)
    }

    /// Keeps only foreground inside `rect` (normalised, top-left origin).
    public func clipped(to rect: CGRect) -> Mask {
        let x0 = Int((rect.minX * Double(width)).rounded()), x1 = Int((rect.maxX * Double(width)).rounded())
        let y0 = Int((rect.minY * Double(height)).rounded()), y1 = Int((rect.maxY * Double(height)).rounded())
        var out = pixels
        for y in 0..<height { for x in 0..<width where x < x0 || x >= x1 || y < y0 || y >= y1 { out[y * width + x] = 0 } }
        return Mask(width: width, height: height, pixels: out)
    }

    // MARK: clean-up (Round 4)

    /// 8-connected components of the foreground: label per pixel (0 = background) and each component's area (index = label - 1).
    private func components() -> (labels: [Int32], areas: [Int]) {
        var labels = [Int32](repeating: 0, count: pixels.count), areas: [Int] = [], stack: [Int] = []
        for start in pixels.indices where pixels[start] > 127 && labels[start] == 0 {
            let id = Int32(areas.count + 1); var n = 0
            labels[start] = id; stack.append(start)
            while let i = stack.popLast() {
                n += 1
                let x = i % width, y = i / width
                for yy in max(0, y - 1)...min(height - 1, y + 1) { for xx in max(0, x - 1)...min(width - 1, x + 1) {
                    let j = yy * width + xx
                    if pixels[j] > 127, labels[j] == 0 { labels[j] = id; stack.append(j) }
                } }
            }
            areas.append(n)
        }
        return (labels, areas)
    }

    /// Keeps the largest component plus any component of at least `minShare` of its area (the other shoe); drops stray blobs.
    public func keepingMainComponents(minShare: Double = 0.15) -> Mask {
        let (labels, areas) = components()
        guard let biggest = areas.max() else { return self }
        let keep = areas.map { Double($0) >= minShare * Double(biggest) }
        return Mask(width: width, height: height, pixels: labels.map { $0 > 0 && keep[Int($0) - 1] ? 255 : 0 })
    }

    /// Background regions not connected to the frame border become foreground (holes in the garment).
    public func filledHoles() -> Mask {
        var outside = [Bool](repeating: false, count: pixels.count), stack: [Int] = []
        func seed(_ i: Int) { if pixels[i] <= 127, !outside[i] { outside[i] = true; stack.append(i) } }
        for x in 0..<width { seed(x); seed((height - 1) * width + x) }
        for y in 0..<height { seed(y * width); seed(y * width + width - 1) }
        while let i = stack.popLast() {
            let x = i % width, y = i / width
            if x > 0 { seed(i - 1) }; if x < width - 1 { seed(i + 1) }
            if y > 0 { seed(i - width) }; if y < height - 1 { seed(i + width) }
        }
        return Mask(width: width, height: height, pixels: pixels.indices.map { pixels[$0] > 127 || !outside[$0] ? 255 : 0 })
    }

    /// Grows the foreground by `r` pixels (the frame border does not count as foreground).
    public func dilated(by r: Int) -> Mask {
        guard r > 0 else { return self }
        let inv = Mask(width: width, height: height, pixels: pixels.map { $0 > 127 ? 0 : 255 })
        let e = inv.eroded(by: r, outsideIsForeground: true)
        return Mask(width: width, height: height, pixels: e.pixels.map { $0 > 127 ? 0 : 255 })
    }

    /// Morphological close: joins gaps and smooths notches narrower than about 2r.
    public func closed(radius r: Int) -> Mask { dilated(by: r).eroded(by: r, outsideIsForeground: true) }

    /// Cut-out clean-up: stray blobs out, holes filled, then a close of ~1% of the short side.
    /// The close runs on a copy of at most 512 px and only adds pixels, so a 2048 px mask stays fast and keeps its exact edge.
    public func cleanedUp() -> Mask {
        let m = keepingMainComponents().filledHoles()
        let side = 512, r = max(1, Int(Double(min(width, height)) * 0.01))
        guard max(width, height) > side else { return m.closed(radius: r) }
        let small = m.resized(maxSide: side)
        let sr = max(1, r * small.width / width)
        let closed = small.closed(radius: sr)
        var out = m.pixels
        for y in 0..<height { for x in 0..<width where out[y * width + x] <= 127 {
            let sx = min(small.width - 1, x * small.width / width), sy = min(small.height - 1, y * small.height / height)
            if closed.pixels[sy * small.width + sx] > 127, small.pixels[sy * small.width + sx] <= 127 { out[y * width + x] = 255 }
        } }
        return Mask(width: width, height: height, pixels: out)
    }
}
