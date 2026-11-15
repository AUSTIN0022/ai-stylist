import CoreGraphics
import Foundation
import Testing
@testable import WardrobeImaging

private func item(_ store: ImageStore) throws -> UUID {
    let id = UUID()
    try store.save(ImageCodec.pngData(solid("B5522B", 80, 100))!, named: ImageStore.cutoutName, for: id)
    try store.save(jpeg(solid("336699", 300, 200)), named: ImageStore.originalName, for: id)
    try store.save(jpeg(solid("F4F4F2", 120, 150)), named: ImageStore.displayName, for: id)
    return id
}

@Test func S2_PS06_productPhotoSavedAndOthersUntouched() async throws {
    let root = tempRoot(); defer { try? FileManager.default.removeItem(at: root) }
    let store = ImageStore(root: root), id = try item(store)
    let before = try [ImageStore.cutoutName, ImageStore.displayName, ImageStore.originalName].map { try store.load($0, for: id) }
    let fake = root.appendingPathComponent("generated.png")
    try ImageCodec.pngData(makeImage(900, 900) { fill($0, "E5E5E5", 0, 0, 900, 900); fill($0, "1F2A44", 200, 150, 500, 600) })!.write(to: fake)

    try await ItemImageProcessor(cutout: FakeCutout(), store: store).saveProductPhoto(from: fake, for: id)

    let out = try #require(ImageCodec.decode(try store.load(ImageStore.productName, for: id)))
    #expect(out.width == 1200 && out.height == 1500)
    let after = try [ImageStore.cutoutName, ImageStore.displayName, ImageStore.originalName].map { try store.load($0, for: id) }
    #expect(before == after)
}

@Test func S2_PS06b_unreadableCompletionWritesNothing() async throws {
    let root = tempRoot(); defer { try? FileManager.default.removeItem(at: root) }
    let store = ImageStore(root: root), id = try item(store)
    let bad = root.appendingPathComponent("bad.png"); try Data("nope".utf8).write(to: bad)
    await #expect(throws: (any Error).self) { try await ItemImageProcessor(cutout: FakeCutout(), store: store).saveProductPhoto(from: bad, for: id) }
    #expect(!FileManager.default.fileExists(atPath: store.url(for: ImageStore.productName, id: id).path))
}

@Test func S2_PS07_preferenceProductOverDisplay() throws {
    let root = tempRoot(); defer { try? FileManager.default.removeItem(at: root) }
    let store = ImageStore(root: root), id = try item(store)
    #expect(store.preferredName(for: id) == ImageStore.displayName)
    try store.save(Data([1]), named: ImageStore.productName, for: id)
    #expect(store.preferredName(for: id) == ImageStore.productName)
    store.removeProductPhoto(for: id)
    #expect(store.preferredName(for: id) == ImageStore.displayName)
    #expect(FileManager.default.fileExists(atPath: store.url(for: ImageStore.cutoutName, id: id).path))
}

private func hexAt(_ img: CGImage, _ x: Int, _ y: Int) -> String {
    let p = PixelBuffer(img); let i = (y * img.width + x) * 4
    return String(format: "%02X%02X%02X", p.data[i], p.data[i + 1], p.data[i + 2])
}

@Test func S2_PS18_generatedPhotoLosesItsBackdrop() async throws {
    let root = tempRoot(); defer { try? FileManager.default.removeItem(at: root) }
    let store = ImageStore(root: root), id = try item(store)
    let gen = root.appendingPathComponent("g.png")
    try ImageCodec.pngData(makeImage(800, 800) { fill($0, "D0D0D0", 0, 0, 800, 800); fill($0, "803F55", 200, 150, 400, 500) })!.write(to: gen)
    // fake mask provider (Vision is never called in tests): the garment is the rectangle
    try await ItemImageProcessor(cutout: FakeCutout(mask: rectMask(100, 100, x: 25, y: 19, rw: 50, rh: 62)), store: store).saveProductPhoto(from: gen, for: id)
    let out = try #require(ImageCodec.decode(try store.load(ImageStore.productName, for: id)))
    #expect(out.width == 1200 && out.height == 1500)
    for (x, y) in [(2, 2), (1197, 2), (2, 1497), (1197, 1497)] { #expect(hexDistance(hexAt(out, x, y), "F4F4F2") <= 2, Comment(rawValue: hexAt(out, x, y))) }
}

@Test func S2_PS18b_failedMaskFallsBackToCentreCrop() async throws {
    let root = tempRoot(); defer { try? FileManager.default.removeItem(at: root) }
    let store = ImageStore(root: root), id = try item(store)
    let gen = root.appendingPathComponent("g.png")
    try ImageCodec.pngData(makeImage(800, 800) { fill($0, "D0D0D0", 0, 0, 800, 800); fill($0, "803F55", 300, 300, 200, 200) })!.write(to: gen)
    try await ItemImageProcessor(cutout: FakeCutout(fail: true), store: store).saveProductPhoto(from: gen, for: id)
    let out = try #require(ImageCodec.decode(try store.load(ImageStore.productName, for: id)))
    #expect(out.width == 1200 && out.height == 1500)
    #expect(hexDistance(hexAt(out, 600, 750), "803F55") <= 3)   // centre crop, no inset card: the garment is where it was
}

@Test func S2_PS16b_savedTemplateBeatsBundled() throws {
    let root = tempRoot(); defer { try? FileManager.default.removeItem(at: root) }
    let bundled = root.appendingPathComponent("bundled.jpg"); try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try jpeg(solid("111111")).write(to: bundled)
    let ts = TemplateStore(directory: root.appendingPathComponent("templates")) { $0 == .tshirtShort ? bundled : nil }
    #expect(ts.url(for: .tshirtShort) == bundled && ts.url(for: .hoodie) == nil && ts.available == [.tshirtShort])
    try ts.save(jpeg(solid("222222")), for: .tshirtShort)
    #expect(ts.url(for: .tshirtShort)?.deletingLastPathComponent().lastPathComponent == "templates")
    #expect(ts.isSaved(.tshirtShort))
    ts.remove(.tshirtShort)
    #expect(ts.url(for: .tshirtShort) == bundled && !ts.isSaved(.tshirtShort))
}

// 15 Nov: no re-cut. Crop 4:5 around the subject, levels the backdrop to #F4F4F2.
@Test func S2_FX07_backdropLevelledAndSubjectInside() {
    let src = makeImage(900, 900) { fill($0, "D8D6D5", 0, 0, 900, 900); fill($0, "202020", 300, 250, 300, 400) }
    let out = Catalogue.productFrame(src, subject: CGRect(x: 1.0 / 3, y: 250.0 / 900, width: 1.0 / 3, height: 400.0 / 900))
    #expect(out.width == 1200 && out.height == 1500)
    for (x, y) in [(2, 2), (1197, 2), (2, 1497), (1197, 1497), (600, 20), (20, 750)] { #expect(hexDistance(hexAt(out, x, y), "F4F4F2") <= 3, Comment(rawValue: hexAt(out, x, y))) }
    let p = PixelBuffer(out); var minX = 1200, maxX = -1, minY = 1500, maxY = -1
    for y in 0..<1500 { for x in 0..<1200 where p.data[(y * 1200 + x) * 4] < 100 { minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y) } }
    #expect(minX > 60 && maxX < 1140 && minY > 60 && maxY < 1440)   // ~9% margin, nothing cut
    #expect(abs((minX + maxX) / 2 - 600) <= 3 && abs((minY + maxY) / 2 - 750) <= 3)
}

@Test func S2_FX07b_subjectNearEdgeStillFullyInside() {
    let src = makeImage(400, 500) { fill($0, "D8D6D5", 0, 0, 400, 500); fill($0, "202020", 0, 20, 120, 460) }   // touches the left edge
    let out = Catalogue.productFrame(src, subject: CGRect(x: 0, y: 0.04, width: 0.3, height: 0.92))
    let p = PixelBuffer(out)
    #expect((0..<1500).allSatisfy { p.data[($0 * 1200) * 4] > 200 })   // left column is backdrop: the subject was padded, not clipped
}
