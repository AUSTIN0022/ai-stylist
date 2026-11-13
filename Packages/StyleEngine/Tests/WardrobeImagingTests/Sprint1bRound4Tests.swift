import CoreGraphics
import StyleEngine
import Testing
@testable import WardrobeImaging

private func perimeter(_ m: Mask) -> Int {
    var n = 0
    for y in 0..<m.height { for x in 0..<m.width where m.pixels[y * m.width + x] > 127 {
        for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
            let xx = x + dx, yy = y + dy
            if xx < 0 || yy < 0 || xx >= m.width || yy >= m.height || m.pixels[yy * m.width + xx] <= 127 { n += 1; break }
        }
    } }
    return n
}

@Test func S1B_U66_holeFilled() {
    var m = rectMask(100, 100, x: 20, y: 20, rw: 60, rh: 60)
    var px = m.pixels
    for y in 40..<55 { for x in 40..<55 { px[y * 100 + x] = 0 } }
    m = Mask(width: 100, height: 100, pixels: px)
    let f = m.filledHoles()
    #expect(f.foregroundCount == 60 * 60)
    // A notch open to the outside is not a hole.
    var open = rectMask(100, 100, x: 20, y: 20, rw: 60, rh: 60).pixels
    for y in 20..<40 { for x in 45..<50 { open[y * 100 + x] = 0 } }
    let o = Mask(width: 100, height: 100, pixels: open)
    #expect(o.filledHoles() == o)
}

@Test func S1B_U67_tinyBlobRemovedShoesKept() {
    let main = rectMask(100, 100, x: 10, y: 10, rw: 60, rh: 60)           // 3600
    var px = main.pixels
    for y in 90..<98 { for x in 85..<94 { px[y * 100 + x] = 255 } }          // 72 px = 2%
    let withBlob = Mask(width: 100, height: 100, pixels: px)
    let cleaned = withBlob.keepingMainComponents()
    #expect(cleaned == main)
    let shoes = Mask.union([rectMask(100, 100, x: 5, y: 40, rw: 30, rh: 30), rectMask(100, 100, x: 60, y: 40, rw: 30, rh: 30)])!
    #expect(shoes.keepingMainComponents() == shoes)
}

@Test func S1B_U68_closeSmoothsJaggedEdge() {
    var px = rectMask(100, 100, x: 20, y: 30, rw: 60, rh: 50).pixels
    for x in stride(from: 21, to: 80, by: 2) { for y in 30..<32 { px[y * 100 + x] = 0 } }   // 1 px wide, 2 deep teeth
    let jagged = Mask(width: 100, height: 100, pixels: px)
    let c = jagged.closed(radius: 2)
    #expect(perimeter(c) < perimeter(jagged))
    let a0 = Double(jagged.foregroundCount), a1 = Double(c.foregroundCount)
    #expect(abs(a1 - a0) / a0 < 0.05)
    // cleanedUp does all three on a big mask without growing the item much
    let big = Mask(width: 1200, height: 900, pixels: [UInt8](repeating: 0, count: 1200 * 900))
    #expect(big.cleanedUp() == big)
}

@Test func S1B_U69_whiteRuleV2() {
    #expect(ColorExtractor.name(forHex: "D2D3CD") == .white)
    #expect(ColorExtractor.name(forHex: "D7D8D2") == .white)
    #expect(ColorExtractor.name(forHex: "C0C0C0") == .silver)
    #expect(ColorExtractor.name(forHex: "F3EBDD") == .cream)
    #expect(ColorExtractor.classify(hex: "D2D3CD").ambiguous)       // L < 90
    #expect(!ColorExtractor.classify(hex: "FFFFFF").ambiguous)
}

private func lightImage(garment: String, surround: String) -> CGImage {
    makeImage(256, 256) { ctx in
        fill(ctx, surround, 0, 0, 256, 256)
        for y in stride(from: 46, to: 210, by: 2) { for x in stride(from: 46, to: 210, by: 2) where ((x + y) / 2) % 2 == 0 {
            fill(ctx, garment, x, y, 2, 2)
        } }
        for y in stride(from: 46, to: 210, by: 2) { for x in stride(from: 46, to: 210, by: 2) where ((x + y) / 2) % 2 == 1 {
            fill(ctx, "E0E0E0", x, y, 2, 2)
        } }
    }
}
private let lightMask = rectMask(100, 100, x: 18, y: 18, rw: 64, rh: 64)

@Test func S1B_U70_lightOnLightNote() {
    #expect(QualityCheck.check(image: lightImage(garment: "F4F4F4", surround: "E8E8E8"), mask: lightMask) == .lightOnLight)
    #expect(QualityCheck.check(image: lightImage(garment: "F4F4F4", surround: "202020"), mask: lightMask) == .ok)
    #expect(QualityVerdict.lightOnLight.message == "Light item on a light surface. A dark sheet or floor gives a cleaner cut-out.")
}

private func lumRange(_ img: CGImage) -> (Int, Int) {
    let b = PixelBuffer(img)
    let v = (0..<b.width * b.height).map { Int(b.data[$0 * 4]) }
    return (v.min()!, v.max()!)
}
@Test func S1B_U71_stretchAndInvert() {
    let low = makeImage(64, 64) { ctx in fill(ctx, "808080", 0, 0, 64, 64); fill(ctx, "909090", 0, 0, 32, 64) }
    let (lo0, hi0) = lumRange(low)
    let s = LabelScanner.contrastStretched(low)!
    let (lo1, hi1) = lumRange(s)
    #expect(hi1 - lo1 > 3 * (hi0 - lo0) && lo1 < 20 && hi1 > 235)
    let bw = makeImage(10, 10) { ctx in fill(ctx, "000000", 0, 0, 5, 10); fill(ctx, "FFFFFF", 5, 0, 5, 10) }
    let inv = PixelBuffer(LabelScanner.inverted(bw)!)
    #expect(inv.rgba(2, 5).0 == 255 && inv.rgba(7, 5).0 == 0)
}

@Test func S1B_U72_threePassesMergeEachLineOnce() {
    let merged = LabelParser.mergeLines(live: ["Slim Fit"], passes: [["WES", "slim  fit", "S"], ["wes", "100% Cotton"], ["WES.", "s", "100% cotton"]])
    #expect(merged == ["Slim Fit", "WES", "S", "100% Cotton"])
}
