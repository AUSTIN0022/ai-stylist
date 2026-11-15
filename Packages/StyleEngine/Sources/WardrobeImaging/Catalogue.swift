import CoreGraphics
import Foundation
import StyleEngine

/// "Catalogue look": cut-out -> upright, neutral colour, clean edge, fixed framing on #F4F4F2 with a soft contact shadow.
/// Deterministic and on-device; no generative AI. Pure functions over pixels so the Mac tests cover it.
public enum Catalogue {
    public static let canvasWidth = 1200, canvasHeight = 1500
    /// Garment bounding box fills this fraction of the canvas (per axis, whichever is tighter).
    public static let fillFraction = 0.82
    public static let background: (r: UInt8, g: UInt8, b: UInt8) = (244, 244, 242)   // #F4F4F2
    static let shadowOpacity: Float = 0.12, shadowOffset = 0.015
    static let pad = 6, workSide = 1500

    /// The display image: 1200x1500 opaque. `original` + `mask` (any size, same aspect as the original) give the photo surround for
    /// white balance; with no mask the outer 6% frame of `original` is the surround; with no original there is no white balance.
    public static func render(cutout: CGImage, original: CGImage?, mask: Mask?, category: StyleEngine.Category?) -> CGImage {
        var pb = PixelBuffer(cutout, maxSide: workSide)
        let gains = original.map { whiteBalanceGains(original: $0, mask: mask) } ?? (1, 1, 1)
        balance(&pb, gains: gains)
        guard let balanced = pb.makeImage() else { return cutout }
        let upright = uprighted(balanced, category: category)

        let up = PixelBuffer(upright)
        guard let box = alphaBounds(up), let crop = upright.cropping(to: box) else { return canvas(nil) }
        return frame(crop)
    }

    /// An already clean opaque image (a generated product photo) on the same canvas, margins and shadow as `render`; no colour changes.
    public static func frame(_ crop: CGImage) -> CGImage {
        let box = CGRect(x: 0, y: 0, width: crop.width, height: crop.height)
        let s = min(fillFraction * Double(canvasWidth) / Double(box.width), fillFraction * Double(canvasHeight) / Double(box.height))
        let tw = max(1, Int((Double(box.width) * s).rounded())), th = max(1, Int((Double(box.height) * s).rounded()))
        let gw = tw + 2 * pad, gh = th + 2 * pad
        let ctx = CGContext(data: nil, width: gw, height: gh, bitsPerComponent: 8, bytesPerRow: 0, space: sRGBSpace,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.interpolationQuality = .high
        ctx.draw(crop, in: CGRect(x: pad, y: pad, width: tw, height: th))
        guard let placed = ctx.makeImage() else { return canvas(nil) }
        return canvas(cleanEdge(PixelBuffer(placed)))
    }


    // MARK: Upright

    /// Principal axis of a mask in degrees, measured clockwise from +x (row 0 = top), and the variance ratio major/minor.
    static func axisAngle(of mask: Mask) -> (degrees: Double, ratio: Double)? {
        var n = 0.0, sx = 0.0, sy = 0.0, sxx = 0.0, syy = 0.0, sxy = 0.0
        for y in 0..<mask.height { for x in 0..<mask.width where mask.pixels[y * mask.width + x] > 127 {
            let fx = Double(x), fy = Double(y)
            n += 1; sx += fx; sy += fy; sxx += fx * fx; syy += fy * fy; sxy += fx * fy
        } }
        guard n > 8 else { return nil }
        let mx = sx / n, my = sy / n
        let u20 = sxx / n - mx * mx, u02 = syy / n - my * my, u11 = sxy / n - mx * my
        let root = (((u20 - u02) / 2) * ((u20 - u02) / 2) + u11 * u11).squareRoot()
        let l1 = (u20 + u02) / 2 + root, l2 = (u20 + u02) / 2 - root
        return (0.5 * atan2(2 * u11, u20 - u02) * 180 / .pi, l1 / max(l2, 1e-9))
    }

    /// Degrees to rotate the image counter-clockwise (visually) to square the garment up; 0 when the axis is unclear or > 25 deg off.
    /// Bottoms and one-pieces: long axis vertical. Everything else: nearest of horizontal (shoulders) / vertical.
    static func correction(for mask: Mask, category: StyleEngine.Category?) -> Double {
        guard let (a, ratio) = axisAngle(of: mask) else { return 0 }
        // Device test (14 Nov): rotating near-square shapes (tees, hoodies with sleeves) made them crooked.
        // ponytail: only clearly long shapes are squared up; a sleeve-aware upright needs the garment's category and keypoints.
        if ratio < 2.0 { return 0 }
        func norm(_ d: Double) -> Double {
            var x = d.truncatingRemainder(dividingBy: 180)
            if x > 90 { x -= 180 }; if x <= -90 { x += 180 }
            return x
        }
        let toH = norm(a), toV = norm(a - 90)
        let d: Double
        switch category {
        case .bottom?, .onePiece?: d = toV
        default: d = abs(toH) <= abs(toV) ? toH : toV
        }
        return abs(d) <= 10 ? d : 0
    }

    /// Angle (|a| <= 25 deg, clockwise like `axisAngle`) at which the rotated bounding box is smallest; 0 unless it saves >= 4% area.
    static func minAreaAngle(_ mask: Mask) -> Double {
        var pts: [(Double, Double)] = []
        let step = max(1, mask.foregroundCount / 4000)
        var k = 0
        for y in 0..<mask.height { for x in 0..<mask.width where mask.pixels[y * mask.width + x] > 127 {
            k += 1; if k % step == 0 { pts.append((Double(x), Double(y))) }
        } }
        guard pts.count > 8 else { return 0 }
        func area(_ deg: Double) -> Double {
            let c = cos(deg * .pi / 180), s = sin(deg * .pi / 180)
            var u0 = Double.infinity, u1 = -Double.infinity, v0 = u0, v1 = u1
            for (x, y) in pts {
                let u = x * c + y * s, v = -x * s + y * c
                u0 = min(u0, u); u1 = max(u1, u); v0 = min(v0, v); v1 = max(v1, v)
            }
            return (u1 - u0) * (v1 - v0)
        }
        let base = area(0)
        var best = (0.0, base)
        for i in -50...50 { let d = Double(i) * 0.5, a = area(d); if a < best.1 - 1e-9 { best = (d, a) } }
        return best.1 <= base * 0.96 ? best.0 : 0
    }

    static func alphaMask(_ image: CGImage) -> Mask {
        let p = PixelBuffer(image, maxSide: 256)
        return Mask(width: p.width, height: p.height, pixels: (0..<p.width * p.height).map { p.data[$0 * 4 + 3] })
    }

    /// The cut-out rotated upright (canvas grows to fit; not cropped).
    static func uprighted(_ image: CGImage, category: StyleEngine.Category?) -> CGImage {
        let d = correction(for: alphaMask(image), category: category)
        guard abs(d) > 0.05 else { return image }
        let t = d * .pi / 180, w = Double(image.width), h = Double(image.height)
        let nw = Int((abs(w * cos(t)) + abs(h * sin(t))).rounded(.up)), nh = Int((abs(w * sin(t)) + abs(h * cos(t))).rounded(.up))
        let ctx = CGContext(data: nil, width: nw, height: nh, bitsPerComponent: 8, bytesPerRow: 0, space: sRGBSpace,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.interpolationQuality = .high
        ctx.translateBy(x: Double(nw) / 2, y: Double(nh) / 2)
        ctx.rotate(by: t)
        ctx.draw(image, in: CGRect(x: -w / 2, y: -h / 2, width: w, height: h))
        return ctx.makeImage() ?? image
    }

    @_optimize(speed)
    static func alphaBounds(_ p: PixelBuffer) -> CGRect? {
        var x0 = p.width, y0 = p.height, x1 = -1, y1 = -1
        p.data.withUnsafeBufferPointer { d in
            for y in 0..<p.height { for x in 0..<p.width where d[(y * p.width + x) * 4 + 3] > 8 {
                if x < x0 { x0 = x }; if x > x1 { x1 = x }; if y < y0 { y0 = y }; if y > y1 { y1 = y }
            } }
        }
        return x1 < 0 ? nil : CGRect(x: x0, y: y0, width: x1 - x0 + 1, height: y1 - y0 + 1)
    }

    // MARK: Colour

    /// Grey-world gains (R, G, B) from the photo surround, clamped to 0.8...1.25 so a coloured table cannot wreck the garment.
    static func whiteBalanceGains(original: CGImage, mask: Mask?) -> (Double, Double, Double) {
        let o = PixelBuffer(original, maxSide: 256)
        var sum = (0.0, 0.0, 0.0), n = 0.0, colourful = 0.0
        let ringX = max(1, o.width * 6 / 100), ringY = max(1, o.height * 6 / 100)
        for y in 0..<o.height { for x in 0..<o.width {
            let surround: Bool
            if let m = mask {
                surround = m.pixels[min(m.height - 1, y * m.height / o.height) * m.width + min(m.width - 1, x * m.width / o.width)] <= 127
            } else {
                surround = x < ringX || y < ringY || x >= o.width - ringX || y >= o.height - ringY
            }
            guard surround else { continue }
            let p = o.rgba(x, y)
            sum.0 += Double(p.0); sum.1 += Double(p.1); sum.2 += Double(p.2); n += 1
            let hi = Double(max(p.0, p.1, p.2)), lo = Double(min(p.0, p.1, p.2))
            if hi > 40, (hi - lo) / hi > 0.35 { colourful += 1 }   // a strongly coloured pixel (print, wood, fabric)
        } }
        guard n >= Double(o.width * o.height) * 0.02, sum.0 > 0, sum.1 > 0, sum.2 > 0 else { return (1, 1, 1) }
        // Device test (14 Nov): a floral sheet is not a grey reference and pushed white tees blue. Skip busy, colourful surrounds.
        if colourful / n > 0.15 { return (1, 1, 1) }
        let grey = (sum.0 + sum.1 + sum.2) / 3
        func g(_ c: Double) -> Double { min(1.18, max(0.85, grey / c)) }
        return (g(sum.0), g(sum.1), g(sum.2))
    }

    /// White balance by `gains`, then mild auto-levels (half way to a full stretch) on the garment's opaque pixels.
    @_optimize(speed)
    static func balance(_ pb: inout PixelBuffer, gains: (Double, Double, Double)) {
        let n = pb.width * pb.height
        let gr = Float(gains.0), gg = Float(gains.1), gb = Float(gains.2)
        pb.data.withUnsafeMutableBufferPointer { d in
            var hist = [Int](repeating: 0, count: 256), opaque = 0
            func straight(_ i: Int) -> (Float, Float, Float)? {
                let a = Float(d[i * 4 + 3]); guard a > 0 else { return nil }
                let k = 255 / a
                return (min(255, Float(d[i * 4]) * k * gr), min(255, Float(d[i * 4 + 1]) * k * gg), min(255, Float(d[i * 4 + 2]) * k * gb))
            }
            for i in 0..<n where d[i * 4 + 3] >= 250 {
                let c = straight(i)!
                hist[Int(0.299 * c.0 + 0.587 * c.1 + 0.114 * c.2)] += 1; opaque += 1
            }
            var lo: Float = 0, hi: Float = 255   // identity unless stretched
            if opaque > 0 {
                var acc = 0
                var l = 0; for v in 0..<256 { acc += hist[v]; if acc * 100 >= opaque { l = v; break } }
                acc = 0
                var h = 255; for v in stride(from: 255, through: 0, by: -1) { acc += hist[v]; if acc * 100 >= opaque { h = v; break } }
                // Only garments that really span the tonal range are stretched (flat or dark ones keep their colour), and only half way.
                if h - l >= 130 { lo = Float(l) * 0.5; hi = Float(h) + (255 - Float(h)) * 0.5 }
            }
            let k = 255 / max(1, hi - lo)
            let scale = 0.5 + 0.5 * k, offset = 0.5 * lo * k    // out = half identity + half full stretch
            for i in 0..<n {
                guard let c = straight(i) else { continue }
                let a = Float(d[i * 4 + 3]) / 255
                d[i * 4] = UInt8(max(0, min(255, c.0 * scale - offset)) * a + 0.5)
                d[i * 4 + 1] = UInt8(max(0, min(255, c.1 * scale - offset)) * a + 0.5)
                d[i * 4 + 2] = UInt8(max(0, min(255, c.2 * scale - offset)) * a + 0.5)
            }
        }
    }

    // MARK: Edge

    /// Straight-colour layer with float alpha.
    struct Layer { let width: Int, height: Int; var r: [Float], g: [Float], b: [Float], a: [Float] }

    /// Feathers the alpha by ~1 px and pulls edge colours (2 px band) toward the interior colour, removing background fringe.
    @_optimize(speed)
    static func cleanEdge(_ p: PixelBuffer) -> Layer {
        let w = p.width, h = p.height, n = w * h
        var r = [Float](repeating: 0, count: n), g = r, b = r, a = r, core = r
        p.data.withUnsafeBufferPointer { d in
            for i in 0..<n {
                let al = d[i * 4 + 3]; guard al > 0 else { continue }
                let k = 255 / Float(al)
                r[i] = min(255, Float(d[i * 4]) * k); g[i] = min(255, Float(d[i * 4 + 1]) * k); b[i] = min(255, Float(d[i * 4 + 2]) * k)
                a[i] = Float(al) / 255
                if al >= 250 { core[i] = 1 }
            }
        }
        let eroded = boxBlur(core, w, h, 2).map { $0 > 0.999 ? Float(1) : 0 }   // opaque 5x5 neighbourhood
        var cr = r, cg = g, cb = b
        for i in 0..<n { cr[i] *= eroded[i]; cg[i] *= eroded[i]; cb[i] *= eroded[i] }
        let bw = boxBlur(eroded, w, h, 3)
        cr = boxBlur(cr, w, h, 3); cg = boxBlur(cg, w, h, 3); cb = boxBlur(cb, w, h, 3)
        let fa = boxBlur(a, w, h, 1)
        for i in 0..<n {
            if eroded[i] == 0, bw[i] > 0.0001 {
                let ir = cr[i] / bw[i], ig = cg[i] / bw[i], ib = cb[i] / bw[i]
                if a[i] > 0 { r[i] = r[i] * 0.25 + ir * 0.75; g[i] = g[i] * 0.25 + ig * 0.75; b[i] = b[i] * 0.25 + ib * 0.75 }
                else { r[i] = ir; g[i] = ig; b[i] = ib }
            }
            a[i] = min(1, max(0, (fa[i] - 0.12) / 0.88))
        }
        return Layer(width: w, height: h, r: r, g: g, b: b, a: a)
    }

    /// Box blur, radius `r`, zero outside the frame.
    @_optimize(speed)
    static func boxBlur(_ src: [Float], _ w: Int, _ h: Int, _ r: Int) -> [Float] {
        let inv = 1 / Float(2 * r + 1)
        var tmp = [Float](repeating: 0, count: w * h), out = tmp
        src.withUnsafeBufferPointer { s in tmp.withUnsafeMutableBufferPointer { t in
            for y in 0..<h {
                let row = y * w
                var sum: Float = 0
                for x in 0..<min(r, w) { sum += s[row + x] }
                for x in 0..<w {
                    if x + r < w { sum += s[row + x + r] }
                    if x - r - 1 >= 0 { sum -= s[row + x - r - 1] }
                    t[row + x] = sum * inv
                }
            }
        } }
        tmp.withUnsafeBufferPointer { t in out.withUnsafeMutableBufferPointer { o in
            var acc = [Float](repeating: 0, count: w)
            for y in 0..<min(r, h) { for x in 0..<w { acc[x] += t[y * w + x] } }
            for y in 0..<h {
                if y + r < h { for x in 0..<w { acc[x] += t[(y + r) * w + x] } }
                if y - r - 1 >= 0 { for x in 0..<w { acc[x] -= t[(y - r - 1) * w + x] } }
                for x in 0..<w { o[y * w + x] = acc[x] * inv }
            }
        } }
        return out
    }

    // MARK: Canvas

    /// Garment centred on the background with the soft contact shadow. Nil layer = empty canvas.
    @_optimize(speed)
    static func canvas(_ layer: Layer?) -> CGImage {
        let W = canvasWidth, H = canvasHeight
        var out = [UInt8](repeating: 255, count: W * H * 4)
        out.withUnsafeMutableBufferPointer { o in
            for i in 0..<W * H { o[i * 4] = background.r; o[i * 4 + 1] = background.g; o[i * 4 + 2] = background.b }
            guard let l = layer else { return }
            let ox = (W - l.width) / 2, oy = (H - l.height) / 2, dy = Int(shadowOffset * Double(H))
            // Shadow: garment alpha shifted down, averaged to 1/4 size, blurred (3 box passes ~ gaussian, sigma ~10 px), sampled bilinearly.
            let SW = W / 4, SH = H / 4
            var low = [Float](repeating: 0, count: SW * SH)
            for gy in 0..<l.height {
                let cy = oy + gy + dy; guard cy >= 0, cy < H else { continue }
                for gx in 0..<l.width {
                    let cx = ox + gx, a = l.a[gy * l.width + gx]
                    if a > 0, cx >= 0, cx < W { low[(cy / 4) * SW + cx / 4] += a / 16 }
                }
            }
            for _ in 0..<3 { low = boxBlur(low, SW, SH, 2) }
            let x0 = max(0, ox - 48), x1 = min(W, ox + l.width + 48), y0 = max(0, oy + dy - 48), y1 = min(H, oy + l.height + dy + 48)
            for y in y0..<y1 {
                let fy = (Float(y) + 0.5) / 4 - 0.5, iy = Int(fy.rounded(.down)), ty = fy - Float(iy)
                for x in x0..<x1 {
                    let fx = (Float(x) + 0.5) / 4 - 0.5, ix = Int(fx.rounded(.down)), tx = fx - Float(ix)
                    func at(_ xx: Int, _ yy: Int) -> Float { xx < 0 || yy < 0 || xx >= SW || yy >= SH ? 0 : low[yy * SW + xx] }
                    let s = (at(ix, iy) * (1 - tx) + at(ix + 1, iy) * tx) * (1 - ty) + (at(ix, iy + 1) * (1 - tx) + at(ix + 1, iy + 1) * tx) * ty
                    guard s > 0 else { continue }
                    let k = 1 - shadowOpacity * min(1, s), i = (y * W + x) * 4
                    o[i] = UInt8(Float(background.r) * k + 0.5); o[i + 1] = UInt8(Float(background.g) * k + 0.5); o[i + 2] = UInt8(Float(background.b) * k + 0.5)
                }
            }
            for gy in 0..<l.height {
                let cy = oy + gy; guard cy >= 0, cy < H else { continue }
                for gx in 0..<l.width {
                    let j = gy * l.width + gx, a = l.a[j], cx = ox + gx
                    guard a > 0, cx >= 0, cx < W else { continue }
                    let i = (cy * W + cx) * 4
                    o[i] = UInt8(Float(o[i]) * (1 - a) + l.r[j] * a + 0.5)
                    o[i + 1] = UInt8(Float(o[i + 1]) * (1 - a) + l.g[j] * a + 0.5)
                    o[i + 2] = UInt8(Float(o[i + 2]) * (1 - a) + l.b[j] * a + 0.5)
                }
            }
        }
        return PixelBuffer(width: W, height: H, data: out).makeImage()!
    }
}

extension Catalogue {
    static let productMargin = 0.09

    /// A generated product photo on the catalogue canvas WITHOUT a re-cut (a second cut-out looks jagged): crop 4:5 centred on the
    /// subject (`subject`: normalised bounds) with a 9% margin, scale to 1200x1500 (areas outside the photo are padded with the
    /// backdrop colour, so the subject is never clipped), then per-channel gain so the backdrop (median of the photo's border) becomes #F4F4F2.
    /// Edges stay as generated. Clamped.
    static func productFrame(_ image: CGImage, subject: CGRect) -> CGImage {
        let iw = Double(image.width), ih = Double(image.height)
        let s = CGRect(x: subject.minX * iw, y: subject.minY * ih, width: subject.width * iw, height: subject.height * ih)
        let k = 1 + 2 * productMargin
        let cw = max(s.width * k, s.height * k * 4 / 5), ch = cw * 5 / 4
        var x0 = s.midX - cw / 2, y0 = s.midY - ch / 2
        // Slide the crop back inside the photo when it fits; otherwise it overhangs and the overhang is padded.
        if cw <= iw { x0 = min(max(0, x0), iw - cw) }
        if ch <= ih { y0 = min(max(0, y0), ih - ch) }
        let bg = borderColour(image)
        let W = canvasWidth, H = canvasHeight, sc = Double(W) / cw
        guard let ctx = CGContext(data: nil, width: W, height: H, bitsPerComponent: 8, bytesPerRow: 0, space: sRGBSpace,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return image }
        ctx.setFillColor(red: bg.0 / 255, green: bg.1 / 255, blue: bg.2 / 255, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: -x0 * sc, y: Double(H) - (-y0 + ih) * sc, width: iw * sc, height: ih * sc))
        guard let canvas = ctx.makeImage() else { return image }
        var pb = PixelBuffer(canvas)
        let target = [Double(background.r), Double(background.g), Double(background.b)]
        let gain = [bg.0, bg.1, bg.2].enumerated().map { min(1.6, max(0.6, target[$0.offset] / max(1, $0.element))) }
        for i in 0..<W * H { for c in 0..<3 { pb.data[i * 4 + c] = UInt8(min(255, (Double(pb.data[i * 4 + c]) * gain[c]).rounded())) } }
        return pb.makeImage() ?? canvas
    }

    /// Median colour of the outer 2% frame of the photo (the backdrop), 0...255 per channel.
    static func borderColour(_ image: CGImage) -> (Double, Double, Double) {
        let p = PixelBuffer(image, maxSide: 256), t = max(1, Int(Double(min(p.width, p.height)) * 0.02))
        var ch: [[UInt8]] = [[], [], []]
        for y in 0..<p.height { for x in 0..<p.width where x < t || y < t || x >= p.width - t || y >= p.height - t {
            for c in 0..<3 { ch[c].append(p.data[(y * p.width + x) * 4 + c]) }
        } }
        let m = ch.map { Double($0.sorted()[$0.count / 2]) }
        return (m[0], m[1], m[2])
    }
}
