import CoreGraphics
import Foundation
import Testing
@testable import WardrobeImaging

/// Navy garment (finely textured) on a transparent canvas, with a white logo square in the middle.
private func garment(w: Int = 300, h: Int = 300, gx: Int = 50, gy: Int = 25, gw: Int = 200, gh: Int = 250, logo: Bool = true) -> CGImage {
    makeImage(w, h) { ctx in
        for y in 0..<gh { for x in 0..<gw {
            let hex = (x + y) % 2 == 0 ? "1F2A44" : "222D47"
            fill(ctx, hex, gx + x, gy + y, 1, 1)
        } }
        if logo { fill(ctx, "FFFFFF", gx + gw / 2 - 30, gy + gh / 2 - 30, 60, 60) }
    }
}

@Test func S2_PS09_swatchAvoidsLogoAndIsOpaque() throws {
    let out = try #require(FabricSwatch.crop(garment()))
    #expect(out.width == 512 && out.height == 512)
    let p = PixelBuffer(out)
    for y in stride(from: 0, to: 512, by: 4) { for x in stride(from: 0, to: 512, by: 4) {
        let c = p.rgba(x, y)
        #expect(c.3 == 255)                                   // fully opaque
        #expect(c.0 < 80 && c.2 < 120)                        // navy: no white logo, no transparent fringe
    } }
}

@Test func S2_PS09_swatchSavedOnce() throws {
    let root = tempRoot(); defer { try? FileManager.default.removeItem(at: root) }
    let store = ImageStore(root: root), id = UUID()
    try store.save(ImageCodec.pngData(garment())!, named: ImageStore.cutoutName, for: id)
    #expect(FabricSwatch.save(for: id, store: store))
    let img = try #require(ImageCodec.decode(try store.load(ImageStore.fabricName, for: id)))
    #expect(img.width == 512 && img.height == 512)
}

@Test func S2_PS10_thinOrTinyMaskReturnsNil() throws {
    #expect(FabricSwatch.crop(garment(gx: 145, gy: 25, gw: 10, gh: 250, logo: false)) == nil)   // thin strap
    #expect(FabricSwatch.crop(garment(gx: 140, gy: 140, gw: 20, gh: 20, logo: false)) == nil)   // tiny
    let root = tempRoot(); defer { try? FileManager.default.removeItem(at: root) }
    let store = ImageStore(root: root), id = UUID()
    try store.save(ImageCodec.pngData(garment(gx: 145, gy: 25, gw: 10, gh: 250, logo: false))!, named: ImageStore.cutoutName, for: id)
    #expect(!FabricSwatch.save(for: id, store: store))
    #expect(!FileManager.default.fileExists(atPath: store.url(for: ImageStore.fabricName, id: id).path))
}
