import CoreGraphics
import Foundation
import Testing
@testable import WardrobeImaging

// Sprint 5 polish: the outfit "sticker" (trimmed garment with a thin white outline) and its cache.

/// RGBA of one pixel (top-left origin) after drawing the image into a known format.
private func pixel(_ img: CGImage, _ x: Int, _ y: Int) -> (r: Int, g: Int, b: Int, a: Int) {
    var data = [UInt8](repeating: 0, count: img.width * img.height * 4)
    let ctx = CGContext(data: &data, width: img.width, height: img.height, bitsPerComponent: 8, bytesPerRow: img.width * 4, space: sRGB,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.draw(img, in: CGRect(x: 0, y: 0, width: img.width, height: img.height))
    let i = (y * img.width + x) * 4
    return (Int(data[i]), Int(data[i + 1]), Int(data[i + 2]), Int(data[i + 3]))
}

/// 100x100 transparent image with an opaque red 20x10 rectangle at (30, 40).
private func redRect() -> CGImage { makeImage(100, 100) { fill($0, "FF0000", 30, 40, 20, 10) } }

@Suite("Sticker maker") struct StickerMakerTests {
    @Test("trims to the garment plus the outline") func trims() throws {
        let s = try #require(StickerMaker.outlined(redRect(), width: 4))
        #expect(s.width == 28 && s.height == 18)
    }

    @Test("white outline hugs the garment, far corners stay transparent, garment pixels are kept") func outline() throws {
        let s = try #require(StickerMaker.outlined(redRect(), width: 4))
        let left = pixel(s, 2, 9)             // 2 px left of the rectangle: inside the outline
        #expect(left.a == 255 && left.r == 255 && left.g == 255 && left.b == 255)
        #expect(pixel(s, 0, 0).a == 0)        // beyond the outline radius from the corner
        let inside = pixel(s, 14, 9)
        #expect(inside.r == 255 && inside.g == 0 && inside.b == 0 && inside.a == 255)
    }

    @Test("nothing to cut out gives nil") func empty() {
        #expect(StickerMaker.outlined(makeImage(20, 20) { _ in }, width: 4) == nil)
    }
}

private final class FakeCut: CutoutProviding, @unchecked Sendable {
    struct Boom: Error {}
    private let lock = NSLock()
    private var _calls = 0, _running = 0, _maxRunning = 0
    var fail = false
    var delay: Duration = .zero
    var calls: Int { lock.withLock { _calls } }
    var maxRunning: Int { lock.withLock { _maxRunning } }
    func cutout(from image: CGImage, box: CGRect?) async throws -> CutoutResult {
        lock.withLock { _calls += 1; _running += 1; _maxRunning = max(_maxRunning, _running) }
        defer { lock.withLock { _running -= 1 } }
        if delay > .zero { try await Task.sleep(for: delay) }
        if fail { throw Boom() }
        return CutoutResult(cutout: redRect(), mask: Mask(width: 1, height: 1, pixels: [255]))
    }
}

private func tempStore() -> ImageStore {
    ImageStore(root: FileManager.default.temporaryDirectory.appendingPathComponent("sticker-\(UUID().uuidString)"))
}

@Suite("Sticker cache") struct StickerCacheTests {
    @Test("product photo is cut out once, outlined, saved; a second call reads the file") func cachesProduct() async throws {
        let store = tempStore(), id = UUID(), cut = FakeCut()
        try store.save(try #require(ImageCodec.jpegData(solid("DDDDDD", 80, 80))), named: ImageStore.productName, for: id)
        let a = try #require(await StickerMaker.image(for: id, store: store, cutout: cut, maxPixel: 400))
        #expect(a.width == 20 + 2 * StickerMaker.outlineWidth && cut.calls == 1)
        #expect(FileManager.default.fileExists(atPath: store.url(for: ImageStore.stickerName, id: id).path))
        _ = await StickerMaker.image(for: id, store: store, cutout: cut, maxPixel: 400)
        #expect(cut.calls == 1)
    }

    @Test("a newer product photo regenerates the sticker") func stale() async throws {
        let store = tempStore(), id = UUID(), cut = FakeCut()
        try store.save(try #require(ImageCodec.jpegData(solid("DDDDDD", 80, 80))), named: ImageStore.productName, for: id)
        _ = await StickerMaker.image(for: id, store: store, cutout: cut, maxPixel: 400)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(60)], ofItemAtPath: store.url(for: ImageStore.productName, id: id).path)
        _ = await StickerMaker.image(for: id, store: store, cutout: cut, maxPixel: 400)
        #expect(cut.calls == 2)
    }

    @Test("no product photo: the cut-out is outlined without another cut-out") func fromCutout() async throws {
        let store = tempStore(), id = UUID(), cut = FakeCut()
        try store.save(try #require(ImageCodec.pngData(redRect())), named: ImageStore.cutoutName, for: id)
        let s = try #require(await StickerMaker.image(for: id, store: store, cutout: cut, maxPixel: 400))
        #expect(s.width == 20 + 2 * StickerMaker.outlineWidth && cut.calls == 0)
    }

    @Test("nothing to work from gives nil") func none() async {
        #expect(await StickerMaker.image(for: UUID(), store: tempStore(), cutout: FakeCut(), maxPixel: 400) == nil)
    }
}

private func storeWithProduct(_ store: ImageStore, _ id: UUID) throws {
    try store.save(try #require(ImageCodec.jpegData(solid("DDDDDD", 80, 80))), named: ImageStore.productName, for: id)
}

@Suite("Sticker speed and safety") struct StickerSpeedTests {
    @Test("a failed cut-out is remembered: not retried until the product photo changes") func negativeCache() async throws {
        let store = tempStore(), id = UUID(), cut = FakeCut(); cut.fail = true
        try storeWithProduct(store, id)
        #expect(await StickerMaker.image(for: id, store: store, cutout: cut, maxPixel: 400) == nil)
        #expect(await StickerMaker.image(for: id, store: store, cutout: cut, maxPixel: 400) == nil)
        #expect(cut.calls == 1)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(60)], ofItemAtPath: store.url(for: ImageStore.productName, id: id).path)
        cut.fail = false
        #expect(await StickerMaker.image(for: id, store: store, cutout: cut, maxPixel: 400) != nil)
        #expect(cut.calls == 2)
    }

    @Test("a built sticker is served from memory: the same image object twice") func memory() async throws {
        let store = tempStore(), id = UUID(), cut = FakeCut()
        try storeWithProduct(store, id)
        let a = try #require(await StickerMaker.image(for: id, store: store, cutout: cut, maxPixel: 400))
        let b = try #require(await StickerMaker.image(for: id, store: store, cutout: cut, maxPixel: 400))
        #expect(a === b)
    }

    @Test("many requests for one item cut it out once") func dedupe() async throws {
        let store = tempStore(), id = UUID(), cut = FakeCut(); cut.delay = .milliseconds(80)
        try storeWithProduct(store, id)
        await withTaskGroup(of: Void.self) { g in
            for _ in 0..<6 { g.addTask { _ = await StickerMaker.image(for: id, store: store, cutout: cut, maxPixel: 400) } }
        }
        #expect(cut.calls == 1)
    }

    @Test("different items are cut out one at a time") func serial() async throws {
        let store = tempStore(), cut = FakeCut(); cut.delay = .milliseconds(40)
        let ids = (0..<4).map { _ in UUID() }
        for id in ids { try storeWithProduct(store, id) }
        await withTaskGroup(of: Void.self) { g in
            for id in ids { g.addTask { _ = await StickerMaker.image(for: id, store: store, cutout: cut, maxPixel: 400) } }
        }
        #expect(cut.calls == 4 && cut.maxRunning == 1)
    }

    @Test("prewarm builds every missing sticker, then does nothing") func prewarm() async throws {
        let store = tempStore(), cut = FakeCut()
        let ids = (0..<3).map { _ in UUID() }
        for id in ids { try storeWithProduct(store, id) }
        await StickerMaker.prewarm(ids: ids, store: store, cutout: cut)
        for id in ids { #expect(FileManager.default.fileExists(atPath: store.url(for: ImageStore.stickerName, id: id).path)) }
        #expect(cut.calls == 3)
        await StickerMaker.prewarm(ids: ids, store: store, cutout: cut)
        #expect(cut.calls == 3)
    }
}

@Suite("Cached thumbnails") struct CachedThumbnailTests {
    @Test("the same file at the same size is decoded once; a rewritten file is decoded again") func cached() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("thumb-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("a.png")
        try #require(ImageCodec.pngData(solid("336699", 80, 80))).write(to: url)
        let a = try #require(ImageCodec.cachedThumbnail(at: url, maxPixel: 64))
        let b = try #require(ImageCodec.cachedThumbnail(at: url, maxPixel: 64))
        #expect(a === b)
        let other = try #require(ImageCodec.cachedThumbnail(at: url, maxPixel: 32))
        #expect(other !== a)
        try #require(ImageCodec.pngData(solid("CC3333", 80, 80))).write(to: url)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(30)], ofItemAtPath: url.path)
        let c = try #require(ImageCodec.cachedThumbnail(at: url, maxPixel: 64))
        #expect(c !== a)
        #expect(ImageCodec.cachedThumbnail(at: dir.appendingPathComponent("missing.png"), maxPixel: 64) == nil)
    }
}
