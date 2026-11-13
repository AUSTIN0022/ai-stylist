import CoreGraphics
import Foundation
import Testing
@testable import WardrobeImaging

private let W = Catalogue.canvasWidth, H = Catalogue.canvasHeight

/// Opaque-pixel bounds of a colour test: (minX, minY, maxX, maxY).
private func bounds(of img: CGImage, where match: (UInt8, UInt8, UInt8) -> Bool) -> (Int, Int, Int, Int)? {
    let p = PixelBuffer(img)
    var b = (p.width, p.height, -1, -1)
    for y in 0..<p.height { for x in 0..<p.width {
        let c = p.rgba(x, y)
        if match(c.0, c.1, c.2) { b = (min(b.0, x), min(b.1, y), max(b.2, x), max(b.3, y)) }
    } }
    return b.2 < 0 ? nil : b
}
private func isRed(_ r: UInt8, _ g: UInt8, _ b: UInt8) -> Bool { r > 200 && g < 60 && b < 60 }

private func redRect(_ w: Int, _ h: Int) -> CGImage { makeImage(w, h) { fill($0, "FF0000", 0, 0, w, h) } }

/// Transparent canvas with a filled rectangle rotated clockwise by `deg` about its centre.
private func tiltedRect(_ rw: Int, _ rh: Int, deg: Double, canvas: Int = 500) -> CGImage {
    makeImage(canvas, canvas) { ctx in
        ctx.translateBy(x: Double(canvas) / 2, y: Double(canvas) / 2); ctx.rotate(by: deg * .pi / 180)
        ctx.setFillColor(rgb("3366AA")); ctx.fill(CGRect(x: -Double(rw) / 2, y: -Double(rh) / 2, width: Double(rw), height: Double(rh)))
    }
}

/// Distance of the principal axis from the nearest of horizontal/vertical, degrees.
private func residual(_ img: CGImage) -> Double {
    let a = Catalogue.axisAngle(of: Catalogue.alphaMask(img))!.degrees
    let m = abs(a).truncatingRemainder(dividingBy: 90)
    return min(m, 90 - m)
}

@Test func S2_CL01_uprightSquaresTiltedGarment() {
    // Device test (14 Nov): rotating near-square tops and > 10 deg tilts made real photos crooked.
    // Only clearly long shapes tilted by at most 10 deg are squared up.
    for deg in [8.0, -8.0, 5.0] {
        let tilted = tiltedRect(300, 120, deg: deg)
        #expect(residual(tilted) > 4)
        #expect(residual(Catalogue.uprighted(tilted, category: nil)) < 1)
    }
    let tall = Catalogue.uprighted(tiltedRect(120, 300, deg: 8), category: .bottom)
    #expect(abs(abs(Catalogue.axisAngle(of: Catalogue.alphaMask(tall))!.degrees) - 90) < 1)
    // More than 10 deg off: left alone.
    #expect(Catalogue.correction(for: Catalogue.alphaMask(tiltedRect(300, 120, deg: 15)), category: nil) == 0)
    // Near-square (a tee or hoodie with sleeves): never rotated.
    #expect(Catalogue.correction(for: Catalogue.alphaMask(tiltedRect(200, 190, deg: 8)), category: .top) == 0)
    #expect(Catalogue.correction(for: Catalogue.alphaMask(tiltedRect(200, 150, deg: 8)), category: .top) == 0)
    let circle = makeImage(500, 500) { ctx in ctx.setFillColor(rgb("3366AA")); ctx.fillEllipse(in: CGRect(x: 100, y: 100, width: 300, height: 300)) }
    #expect(Catalogue.correction(for: Catalogue.alphaMask(circle), category: nil) == 0)
}

@Test func S2_CL08_colourfulSurroundSkipsWhiteBalance() {
    // Device test (14 Nov): a floral sheet pushed white tees blue. A busy, colourful surround is not a grey reference.
    let original = makeImage(200, 200) { ctx in
        for y in stride(from: 0, to: 200, by: 10) { for x in stride(from: 0, to: 200, by: 10) {
            fill(ctx, ["F2F0EA", "2F5FD0", "F08A24", "8A8A8A"][(x / 10 + y / 10) % 4], x, y, 10, 10)
        } }
        fill(ctx, "E8E2D6", 60, 60, 80, 80)
    }
    let g = Catalogue.whiteBalanceGains(original: original, mask: rectMask(200, 200, x: 60, y: 60, rw: 80, rh: 80))
    #expect(g.0 == 1 && g.1 == 1 && g.2 == 1)
}

@Test func S2_CL02_greyWorldRemovesBlueCast() {
    // Neutral grey garment photographed under a blue cast; the whole photo (surround included) is tinted.
    func tint(_ v: Double) -> String { String(format: "%02X%02X%02X", Int(v * 0.9), Int(v * 0.97), Int(v * 1.1)) }
    let original = makeImage(200, 200) { fill($0, tint(200), 0, 0, 200, 200); fill($0, tint(120), 60, 60, 80, 80) }
    let mask = rectMask(200, 200, x: 60, y: 60, rw: 80, rh: 80)
    let cut = makeImage(80, 80) { fill($0, tint(120), 0, 0, 80, 80) }
    func chroma(_ img: CGImage) -> Double {
        let c = PixelBuffer(img).rgba(W / 2, H / 2)
        let lab = labOf(Double(c.0), Double(c.1), Double(c.2))
        return (lab.1 * lab.1 + lab.2 * lab.2).squareRoot()
    }
    #expect(chroma(Catalogue.render(cutout: cut, original: nil, mask: nil, category: nil)) > 8)        // without WB the cast shows
    #expect(chroma(Catalogue.render(cutout: cut, original: original, mask: mask, category: nil)) < 3)
    // No mask: the outer frame is the surround.
    #expect(chroma(Catalogue.render(cutout: cut, original: original, mask: nil, category: nil)) < 3)
}

@Test func S2_CL03_framingIs82PercentAndCentred() {
    for (w, h) in [(400, 800), (300, 300), (900, 500)] {
        let img = Catalogue.render(cutout: redRect(w, h), original: nil, mask: nil, category: nil)
        #expect(img.width == W && img.height == H)
        let b = bounds(of: img, where: isRed)!
        let bw = Double(b.2 - b.0 + 1), bh = Double(b.3 - b.1 + 1)
        // The tighter axis fills 82% of its canvas side.
        let fx = bw / Double(W), fy = bh / Double(H)
        #expect(abs(max(fx, fy) - 0.82) < 0.01)
        #expect(abs(Double(b.0 + b.2 + 1) / 2 - Double(W) / 2) < Double(W) * 0.01)
        #expect(abs(Double(b.1 + b.3 + 1) / 2 - Double(H) / 2) < Double(H) * 0.01)
    }
    // The tall item uses the long side: 82% of 1500.
    let b = bounds(of: Catalogue.render(cutout: redRect(400, 800), original: nil, mask: nil, category: nil), where: isRed)!
    #expect(abs(Double(b.3 - b.1 + 1) / Double(H) - 0.82) < 0.01)
}

@Test func S2_CL04_backgroundCornerIsF4F4F2() {
    let img = Catalogue.render(cutout: redRect(300, 400), original: nil, mask: nil, category: nil)
    let p = PixelBuffer(img)
    for (x, y) in [(0, 0), (W - 1, 0), (0, H - 1), (W - 1, H - 1), (5, H / 2), (W / 2, 3)] {
        let c = p.rgba(x, y)
        #expect(c.0 == 0xF4 && c.1 == 0xF4 && c.2 == 0xF2 && c.3 == 255)
    }
}

@Test func S2_CL05_shadowOnlyBelowGarment() {
    let img = Catalogue.render(cutout: redRect(400, 600), original: nil, mask: nil, category: nil)
    let b = bounds(of: img, where: isRed)!
    let p = PixelBuffer(img), cx = (b.0 + b.2) / 2
    for dy in [10, 30, 60] { let c = p.rgba(cx, b.1 - dy); #expect(c.0 == 0xF4 && c.1 == 0xF4 && c.2 == 0xF2) }   // nothing above
    let under = p.rgba(cx, b.3 + 6)
    #expect(under.0 < 0xF4 - 12 && under.0 == under.1 && under.2 < 0xF2)                                        // visible, neutral, below
    #expect(p.rgba(cx, b.3 + 6).0 < p.rgba(cx, b.3 + 60).0)                                                      // fades out downwards
    let far = p.rgba(cx, min(H - 1, b.3 + 150)); #expect(far.0 == 0xF4)
    // Opacity is ~12% at most: never darker than 88% of the background.
    #expect(Int(under.0) >= Int(Double(0xF4) * 0.87))
}

@Test func S2_CL06_refreshLeavesCutoutAndOriginalByteIdentical() throws {
    let root = tempRoot(); defer { try? FileManager.default.removeItem(at: root) }
    let store = ImageStore(root: root), id = UUID()
    let originalData = jpeg(makeImage(300, 200) { fill($0, "C8C8C8", 0, 0, 300, 200); fill($0, "AA2222", 100, 50, 100, 100) })
    let cutData = ImageCodec.pngData(makeImage(100, 100) { fill($0, "AA2222", 0, 0, 100, 100) })!
    try store.save(originalData, named: ImageStore.originalName, for: id)
    try store.save(cutData, named: ImageStore.cutoutName, for: id)
    try store.save(Data([1, 2, 3]), named: ImageStore.displayName, for: id)
    try ItemImageProcessor(cutout: FakeCutout(), store: store).refreshDisplay(for: id, category: .top)
    #expect(try store.load(ImageStore.originalName, for: id) == originalData)
    #expect(try store.load(ImageStore.cutoutName, for: id) == cutData)
    let display = try #require(ImageCodec.decode(try store.load(ImageStore.displayName, for: id)))
    #expect(display.width == W && display.height == H)
    // A missing cut-out is an error, not a blank tile.
    #expect(throws: (any Error).self) { try ItemImageProcessor(cutout: FakeCutout(), store: store).refreshDisplay(for: UUID(), category: nil) }
}

@Test func S2_CL07_twoThousandPixelInputUnder300ms() {
    let original = makeImage(2048, 2048) { fill($0, "BDB6AA", 0, 0, 2048, 2048) }
    let mask = rectMask(256, 256, x: 40, y: 20, rw: 170, rh: 210)
    let cut = makeImage(1800, 2000) { ctx in
        ctx.setFillColor(rgb("1A1A22")); ctx.fillEllipse(in: CGRect(x: 100, y: 50, width: 1600, height: 1900))
        ctx.fill(CGRect(x: 0, y: 300, width: 1800, height: 500))
    }
    _ = Catalogue.render(cutout: cut, original: original, mask: mask, category: .top)       // warm-up (CG contexts, caches)
    let t0 = ContinuousClock.now
    _ = Catalogue.render(cutout: cut, original: original, mask: mask, category: .top)
    let ms = (ContinuousClock.now - t0) / .milliseconds(1)
    print("catalogue render ms:", ms)
    // The 300 ms gate is for optimised builds (release: ~50 ms). Debug (-Onone) is ~50x slower, so it only guards against a blow-up.
    #if DEBUG
    #expect(ms < 10_000)
    #else
    #expect(ms < 300)
    #endif
}

private func labOf(_ r: Double, _ g: Double, _ b: Double) -> (Double, Double, Double) {
    func lin(_ v: Double) -> Double { let c = v / 255; return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
    let R = lin(r), G = lin(g), B = lin(b)
    let X = (0.4124 * R + 0.3576 * G + 0.1805 * B) / 0.95047, Y = 0.2126 * R + 0.7152 * G + 0.0722 * B, Z = (0.0193 * R + 0.1192 * G + 0.9505 * B) / 1.08883
    func f(_ t: Double) -> Double { t > 0.008856 ? cbrt(t) : 7.787 * t + 16 / 116 }
    return (116 * f(Y) - 16, 500 * (f(X) - f(Y)), 200 * (f(Y) - f(Z)))
}
