import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import WardrobeImaging

@Test func S1_U20_orientationNormalised() throws {
    // 40x20 stored pixels, red left half, blue right half, flagged "rotated right" (EXIF 6).
    let stored = makeImage(40, 20) { fill($0, "FF0000", 0, 0, 20, 20); fill($0, "0000FF", 20, 0, 20, 20) }
    let data = NSMutableData()
    let dest = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, stored, [kCGImagePropertyOrientation: 6] as CFDictionary)
    #expect(CGImageDestinationFinalize(dest))

    let img = try #require(ImageCodec.decode(data as Data))
    #expect(img.width == 20 && img.height == 40)
    let px = PixelBuffer(img)
    #expect(px.rgba(10, 5).0 > 200 && px.rgba(10, 5).2 < 50)      // top is red
    #expect(px.rgba(10, 35).2 > 200 && px.rgba(10, 35).0 < 50)    // bottom is blue
}

@Test func S1_U21_saveAndLoad() throws {
    let root = tempRoot(); defer { try? FileManager.default.removeItem(at: root) }
    let store = ImageStore(root: root), id = UUID()
    let files: [(String, Data)] = [(ImageStore.originalName, Data([1, 2, 3])), (ImageStore.cutoutName, Data([4, 5])), (ImageStore.displayName, Data([6]))]
    for (name, bytes) in files { try store.save(bytes, named: name, for: id) }
    for (name, bytes) in files { #expect(try store.load(name, for: id) == bytes) }
}

@Test func S1_U22_deleteRemovesFolder() throws {
    let root = tempRoot(); defer { try? FileManager.default.removeItem(at: root) }
    let store = ImageStore(root: root), id = UUID()
    try store.save(Data([1]), named: ImageStore.originalName, for: id)
    #expect(FileManager.default.fileExists(atPath: store.folder(for: id).path))
    store.deleteItem(id)
    #expect(!FileManager.default.fileExists(atPath: store.folder(for: id).path))
    store.deleteItem(id)   // deleting twice is harmless
}

@Test func S1_U24_displayImage() {
    let cut = makeImage(200, 100) { fill($0, "FF0000", 0, 0, 200, 100) }
    let d = Compositor.display(from: cut, side: 256)
    #expect(d.width == 256 && d.height == 256)
    let px = PixelBuffer(d)
    for (x, y) in [(0, 0), (255, 0), (0, 255), (255, 255)] { #expect(px.rgba(x, y).0 > 250 && px.rgba(x, y).1 > 250 && px.rgba(x, y).2 > 250) }
    // garment centred: the red band's vertical extent is symmetric
    var minY = 256, maxY = 0
    for y in 0..<256 where px.rgba(128, y).1 < 128 { minY = min(minY, y); maxY = max(maxY, y) }
    #expect(abs(minY - (255 - maxY)) <= 2)
    #expect(px.rgba(128, 128).0 > 200 && px.rgba(128, 128).1 < 50)
}

@Test func S1_U25_mergeMaskInstances() throws {
    let a = rectMask(100, 100, x: 10, y: 10, rw: 10, rh: 10)
    let b = rectMask(100, 100, x: 70, y: 70, rw: 10, rh: 10)
    let merged = try #require(Mask.union([a, b]))
    #expect(merged.bounds == CGRect(x: 10, y: 10, width: 70, height: 70))
    let cut = try #require(Compositor.cutout(of: solid("FF0000"), mask: merged, margin: 0))
    #expect(cut.width >= 70 && cut.height >= 70)
    #expect(Mask.union([]) == nil)
}

@Test func maskErodeAndCutoutTransparency() throws {
    let m = rectMask(50, 50, x: 10, y: 10, rw: 20, rh: 20)
    #expect(m.eroded(by: 2).bounds == CGRect(x: 12, y: 12, width: 16, height: 16))
    let cut = try #require(Compositor.cutout(of: solid("00FF00", 50, 50), mask: m, margin: 2))
    let px = PixelBuffer(cut)
    #expect(px.rgba(0, 0).3 == 0)                  // margin is transparent
    #expect(px.rgba(cut.width / 2, cut.height / 2).3 == 255)
}
