import CoreGraphics
import Foundation
import StyleEngine
import SwiftData
import Testing
import WardrobeImaging
@testable import AIStylist

// Sprint 2 product photos (Image Playground). The sheet is replaced by `deliver(url)` / `cancel()`; no real generation.

private func flat(_ hex: String, _ w: Int, _ h: Int) -> CGImage {
    let v = UInt32(hex, radix: 16) ?? 0
    let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setFillColor(red: CGFloat((v >> 16) & 255) / 255, green: CGFloat((v >> 8) & 255) / 255, blue: CGFloat(v & 255) / 255, alpha: 1)
    ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
    return ctx.makeImage()!
}

/// Stands in for Vision: the whole image is the garment.
private struct FakeCutout: CutoutProviding {
    var fail = false
    func cutout(from image: CGImage, box: CGRect?) async throws -> CutoutResult {
        if fail { throw CutoutError.noSubject }
        var px = [UInt8](repeating: 0, count: 100 * 100)
        for y in 20..<80 { for x in 25..<75 { px[y * 100 + x] = 255 } }
        return CutoutResult(cutout: flat("803F55", 200, 240), mask: Mask(width: 100, height: 100, pixels: px))
    }
}

@MainActor private struct PRig {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("ps-\(UUID().uuidString)")
    let store: ImageStore, container: ModelContainer, item: Item
    var context: ModelContext { container.mainContext }
    init() throws {
        store = ImageStore(root: root.appendingPathComponent("items"))
        container = try ModelContainer(for: Schema(Item.allModels), configurations: ModelConfiguration(url: root.appendingPathComponent("t.store")))
        item = Item(originalFile: ImageStore.originalName, cutoutFile: ImageStore.cutoutName, displayFile: ImageStore.displayName)
        try store.save(ImageCodec.pngData(flat("1F2A44", 400, 500))!, named: ImageStore.cutoutName, for: item.id)
        try store.save(ImageCodec.jpegData(flat("336699", 300, 200))!, named: ImageStore.originalName, for: item.id)
        try store.save(ImageCodec.jpegData(flat("F4F4F2", 120, 150))!, named: ImageStore.displayName, for: item.id)
        var t = ItemTags(); t.category = .top; t.subcategory = .hoodie; t.fabric = .fleece; t.sleeve = .long
        item.aiRawData = try JSONEncoder().encode(t); item.colorNames = ["navy"]
        context.insert(item)
    }
    var templates: TemplateStore = TemplateStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent("tpl-\(UUID().uuidString)")) { _ in nil }
    func session(cutout: any CutoutProviding = FakeCutout()) -> ProductShotSession {
        ProductShotSession(store: store, context: context, cutout: cutout, templates: templates)
    }
    func generated() throws -> URL {
        let u = root.appendingPathComponent("gen-\(UUID().uuidString).png")
        try ImageCodec.pngData(flat("D0D0D0", 800, 800))!.write(to: u)
        return u
    }
    func rows() throws -> [AIRequestLog] { try context.fetch(FetchDescriptor<AIRequestLog>()) }
}

@MainActor @Test func S2_PS06_app_completionWritesProductAndLogs() async throws {
    let r = try PRig(), s = r.session()
    let url = try r.generated()
    let task = Task { @MainActor in await s.make(for: r.item) }
    while !s.isPresented { await Task.yield() }
    #expect(s.prompt.contains("navy fleece") && s.prompt.contains("hoodie"))
    #expect(s.swatch != nil && s.sourceImage != nil)   // fabric.jpg is made on demand when missing
    s.deliver(url)
    #expect(await task.value == .saved)
    let out = try #require(ImageCodec.decode(try r.store.load(ImageStore.productName, for: r.item.id)))
    #expect(out.width == 1200 && out.height == 1500)
    #expect(r.store.preferredName(for: r.item.id) == ImageStore.productName)
    let rows = try r.rows()
    #expect(rows.count == 1 && rows[0].purpose == "productShot" && rows[0].provider == "imagePlayground" && rows[0].success)
    let d = try #require(r.item.productDescriptor)
    #expect(d.prompt == s.prompt && d.swatchFile == ImageStore.fabricName && rows[0].detail?.contains(d.prompt) == true)
    // regeneration reuses the stored description
    let again = r.session(); let t2 = Task { @MainActor in await again.make(for: r.item) }
    while !again.isPresented { await Task.yield() }
    #expect(again.prompt == d.prompt); again.cancel(); _ = await t2.value
    #expect(!s.isPresented)
}

@MainActor @Test func S2_PS07_app_removeFallsBackToDisplay() async throws {
    let r = try PRig(), s = r.session()
    let task = Task { @MainActor in await s.make(for: r.item) }
    while !s.isPresented { await Task.yield() }
    s.deliver(try r.generated()); _ = await task.value
    ProductShotSession.removeProductPhoto(r.item, store: r.store)
    #expect(r.store.preferredName(for: r.item.id) == ImageStore.displayName)
}

@MainActor @Test func S2_PS08_cancelWritesNothingAndLogsCancelled() async throws {
    let r = try PRig(), s = r.session()
    let task = Task { @MainActor in await s.make(for: r.item) }
    while !s.isPresented { await Task.yield() }
    s.cancel()
    #expect(await task.value == .cancelled)
    #expect(!FileManager.default.fileExists(atPath: r.store.url(for: ImageStore.productName, id: r.item.id).path))
    let rows = try r.rows()
    #expect(rows.count == 1 && rows[0].purpose == "productShot" && !rows[0].success && rows[0].errorText?.lowercased().contains("cancel") == true)
}

@MainActor @Test func S2_PS08b_unreadableCompletionLogsFailure() async throws {
    let r = try PRig(), s = r.session()
    let bad = r.root.appendingPathComponent("bad.png"); try FileManager.default.createDirectory(at: r.root, withIntermediateDirectories: true)
    try Data("x".utf8).write(to: bad)
    let task = Task { @MainActor in await s.make(for: r.item) }
    while !s.isPresented { await Task.yield() }
    s.deliver(bad)
    if case .failed = await task.value {} else { Issue.record("expected failed") }
    #expect(try r.rows().first?.success == false)
    #expect(!FileManager.default.fileExists(atPath: r.store.url(for: ImageStore.productName, id: r.item.id).path))
}

@MainActor @Test func S2_PS19_overlayStateMachine() async throws {
    // saved path: idle -> preparing -> sheet -> saving -> idle
    let r = try PRig(), s = r.session()
    #expect(s.overlay == .idle)
    let task = Task { @MainActor in await s.make(for: r.item) }
    await Task.yield()
    #expect(s.overlay == .preparing)   // set before anything slow, so the dim shows at once
    while !s.isPresented { await Task.yield() }
    #expect(s.overlay == .sheet)
    s.deliver(try r.generated())
    #expect(s.overlay == .saving)
    #expect(await task.value == .saved)
    #expect(s.overlay == .idle && s.errorMessage == nil)

    // cancel from the sheet
    let c = r.session(); let t2 = Task { @MainActor in await c.make(for: r.item) }
    while !c.isPresented { await Task.yield() }
    c.cancel(); _ = await t2.value
    #expect(c.overlay == .idle && c.errorMessage == nil)

    // failure: error shown, back to idle
    let f = r.session(); let t3 = Task { @MainActor in await f.make(for: r.item) }
    while !f.isPresented { await Task.yield() }
    let bad = r.root.appendingPathComponent("bad.png"); try Data("x".utf8).write(to: bad)
    f.deliver(bad); _ = await t3.value
    #expect(f.overlay == .idle && f.errorMessage != nil)
}

@MainActor @Test func S2_PS16c_sessionUsesTemplateForSolidItemsAndCutoutForPrints() async throws {
    var r = try PRig()
    let tpl = r.root.appendingPathComponent("tpl.jpg"); try FileManager.default.createDirectory(at: r.root, withIntermediateDirectories: true)
    try ImageCodec.jpegData(flat("777777", 640, 800))!.write(to: tpl)
    r.templates = TemplateStore(directory: r.root.appendingPathComponent("templates")) { $0 == .hoodie ? tpl : nil }
    let s = r.session()
    let t = Task { @MainActor in await s.make(for: r.item) }
    while !s.isPresented { await Task.yield() }
    #expect(s.sourceImage?.width == 640)   // template, not the 400x500 cut-out
    s.cancel(); _ = await t.value
    var tags = r.item.tags; tags.pattern = .stripe; r.item.aiRawData = try JSONEncoder().encode(tags)
    let s2 = r.session(); let t2 = Task { @MainActor in await s2.make(for: r.item) }
    while !s2.isPresented { await Task.yield() }
    #expect(s2.sourceImage?.width == 400)
    s2.cancel(); _ = await t2.value
}

@MainActor @Test func S2_PS15b_bundledTshirtTemplateIsInTheApp() throws {
    let url = try #require(TemplateStore.standard.url(for: .tshirtShort), "tshirt-short.jpg missing from the app bundle")
    print("bundled template path:", url.path)
    #expect(ImageCodec.thumbnail(at: url, maxPixel: 256) != nil)
}

@MainActor @Test func S2_PS20_app_missingSleeveAsksThenSavesCorrection() async throws {
    let r = try PRig()
    var t = r.item.tags; t.category = .top; t.subcategory = .tshirt; t.fabric = .cotton; t.sleeve = nil
    r.item.aiRawData = try JSONEncoder().encode(t)
    r.item.setOverride(\.sleeve, to: nil, context: r.context)
    let s = r.session()
    let task = Task { @MainActor in await s.make(for: r.item) }
    while !s.askingSleeve { await Task.yield() }
    #expect(!s.isPresented)
    s.answerSleeve(.short)
    while !s.isPresented { await Task.yield() }
    #expect(s.sentence.contains("short-sleeve tshirt"))
    #expect(r.item.userOverrides.sleeve == .short && r.item.aiRaw.sleeve == nil)   // a user correction, AI raw untouched
    s.cancel(); _ = await task.value

    // dismissing the question cancels without opening the sheet
    let r2 = try PRig(); var t2 = r2.item.tags; t2.category = .top; t2.subcategory = .tshirt; t2.sleeve = nil; r2.item.aiRawData = try JSONEncoder().encode(t2)
    let s2 = r2.session(); let task2 = Task { @MainActor in await s2.make(for: r2.item) }
    while !s2.askingSleeve { await Task.yield() }
    s2.answerSleeve(nil)
    #expect(await task2.value == .cancelled && !s2.isPresented && s2.overlay == .idle)
}
