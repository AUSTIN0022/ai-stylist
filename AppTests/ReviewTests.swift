import CoreGraphics
import Foundation
import StyleEngine
import SwiftData
import Testing
import WardrobeImaging
@testable import AIStylist

// Review-step logic with a fake cut-out provider and fake label text: no Vision, no real model.

private struct FakeCutout: CutoutProviding {
    var hex = "151B26"   // ambiguous black
    func cutout(from image: CGImage, box: CGRect?) async throws -> CutoutResult {
        let cut = flat(hex)
        return CutoutResult(cutout: cut, mask: Mask(width: 20, height: 20, pixels: [UInt8](repeating: 255, count: 400)))
    }
}

private func flat(_ hex: String, _ w: Int = 80, _ h: Int = 100) -> CGImage {
    let v = UInt32(hex, radix: 16) ?? 0
    let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setFillColor(red: CGFloat((v >> 16) & 255) / 255, green: CGFloat((v >> 8) & 255) / 255, blue: CGFloat(v & 255) / 255, alpha: 1)
    ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
    return ctx.makeImage()!
}
private let photoData = ImageCodec.jpegData(flat("336699", 300, 200))!
private let labelText = "WES\n100% ORGANIC COTTON\nSLIM FIT\nS"

@MainActor private struct Rig {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("review-\(UUID().uuidString)")
    let store: ImageStore, model: ReviewModel, container: ModelContainer
    var context: ModelContext { container.mainContext }
    init(hex: String = "151B26", blurry: Bool = false, tagger: (any ItemTagger)? = nil) throws {
        store = ImageStore(root: root.appendingPathComponent("items"))
        model = ReviewModel(processor: ItemImageProcessor(cutout: FakeCutout(hex: hex), store: store), store: store, tagger: tagger,
                            scan: { _ in (labelText, "2050032266712") }, isBlurry: { _, _ in blurry })
        container = try ModelContainer(for: Schema(Item.allModels), configurations: ModelConfiguration(url: root.appendingPathComponent("t.store")))
        model.logContext = container.mainContext
    }
    /// A second review session over the same store and database (Review again / Sort these).
    func makeModel(tagger: (any ItemTagger)? = nil) -> ReviewModel {
        let m = ReviewModel(processor: ItemImageProcessor(cutout: FakeCutout(), store: store), store: store, tagger: tagger,
                            scan: { _ in (labelText, nil) }, isBlurry: { _, _ in false })
        m.logContext = context
        return m
    }
    func items() throws -> [Item] { try context.fetch(FetchDescriptor<Item>()) }
    func logs() throws -> [AIRequestLog] { try context.fetch(FetchDescriptor<AIRequestLog>()) }
    func start(_ n: Int) async { model.begin(count: n) { _ in photoData }; await model.idle() }
    func count() throws -> Int { try context.fetchCount(FetchDescriptor<Item>()) }
    func cleanup() { try? FileManager.default.removeItem(at: root) }
}

@MainActor @Test func S1B_I01_saveDiscardRetake() async throws {
    let r = try Rig(); defer { r.cleanup() }
    await r.start(3)
    let ids = r.model.photos.map(\.id)
    let discardedItem = try #require(r.model.photos[1].processed).itemID
    let retakenItem = try #require(r.model.photos[2].processed).itemID
    r.model.save(ids[0], context: r.context)
    r.model.discard(ids[1])
    r.model.retake(ids[2])
    #expect(try r.count() == 1)
    #expect(!FileManager.default.fileExists(atPath: r.store.folder(for: discardedItem).path))
    #expect(!FileManager.default.fileExists(atPath: r.store.folder(for: retakenItem).path))
    #expect(r.model.retakeID == ids[2] && r.model.photo(ids[2])?.status == .processing)
    await r.model.replace(ids[2], data: photoData, box: nil)
    #expect(r.model.retakeID == nil && r.model.photo(ids[2])?.status == .ready)
    r.model.save(ids[2], context: r.context)
    #expect(try r.count() == 2 && r.model.isFinished)
}

@MainActor @Test func S1B_I02_colourAnswerIsUserCorrection() async throws {
    let r = try Rig(); defer { r.cleanup() }
    await r.start(1)
    let p = try #require(r.model.photos.first)
    #expect(r.model.askColor(p) && r.model.colorChoices(p).first == p.processed?.colorNames.first)
    let hex = try #require(p.processed?.hexColors.first)
    r.model.answerColor(p.id, .black)
    let item = try #require(r.model.save(p.id, context: r.context))
    #expect(item.colorNames.first == "black" && item.hexColors.first == hex)
    #expect(item.aiRawData == nil)
}

@MainActor @Test func S1B_I03_fitAnswerThenSkip() async throws {
    let r = try Rig(); defer { r.cleanup() }
    await r.start(2)
    let ids = r.model.photos.map(\.id)
    r.model.answerFit(ids[0], .relaxed); r.model.skipFit(ids[1])
    let a = try #require(r.model.save(ids[0], context: r.context)), b = try #require(r.model.save(ids[1], context: r.context))
    #expect(a.tags.fit == .relaxed && a.userOverridesData != nil)
    #expect(b.tags.fit == nil && b.userOverridesData == nil)
    #expect(a.aiRawData == nil && b.aiRawData == nil)
}

@MainActor @Test func S1B_I04_scanLabelStoresDataAndImage() async throws {
    let r = try Rig(); defer { r.cleanup() }
    await r.start(1)
    let id = try #require(r.model.photos.first).id
    await r.model.scanLabel(id, photo: photoData)
    let draft = try #require(r.model.labelDraft)
    #expect(draft.data.brand == "Westside" && draft.data.size == "S" && draft.data.barcode == "2050032266712")
    r.model.confirmLabel(draft.data)
    let item = try #require(r.model.save(id, context: r.context))
    #expect(FileManager.default.fileExists(atPath: r.store.url(for: ImageStore.labelName, id: item.id).path))
    #expect(item.label?.brand == "Westside")
    #expect(item.tags.fabric == .cotton && item.tags.fit == .slim)
}

@MainActor @Test func S1B_I05_nothingSavedBeforeSave() async throws {
    let r = try Rig(); defer { r.cleanup() }
    await r.start(3)
    r.model.answerFit(r.model.photos[0].id, .slim)
    #expect(try r.count() == 0 && !r.model.isFinished)
    r.model.discardAll()
    #expect(try r.count() == 0 && r.model.isFinished)
}

// MARK: Round 2 (S1B-I07...I10)

@MainActor @Test func S1B_I07_categoryAnswerLeavesUnsorted() async throws {
    let r = try Rig(); defer { r.cleanup() }
    await r.start(2)
    let ids = r.model.photos.map(\.id)
    let p = try #require(r.model.photo(ids[0]))
    #expect(r.model.askCategory(p))
    r.model.answerCategory(ids[0], .top)
    r.model.answerSubcategory(ids[0], .tshirt)
    #expect(r.model.photo(ids[0]).map { !r.model.askCategory($0) } == true)
    let a = try #require(r.model.save(ids[0], context: r.context)), b = try #require(r.model.save(ids[1], context: r.context))
    #expect(a.tags.category == .top && a.tags.subcategory == .tshirt && a.aiRawData == nil)
    let titles = WardrobeView.sections(for: [a, b]).map { ($0.title, $0.items.map(\.id)) }
    #expect(titles.first { $0.0 == "Top" }?.1 == [a.id])
    #expect(titles.first { $0.0 == "Unsorted" }?.1 == [b.id])
}

@MainActor @Test func S1B_I08_editLabelSize() async throws {
    let r = try Rig(); defer { r.cleanup() }
    await r.start(1)
    let id = try #require(r.model.photos.first).id
    var l = LabelData(); l.brand = "Zara"; l.size = "A"
    await r.model.scanLabel(id, photo: photoData)
    r.model.confirmLabel(l)
    r.model.answerFit(id, .slim)
    let item = try #require(r.model.save(id, context: r.context))
    #expect(item.label?.size == "A")
    var edited = try #require(item.label); edited.size = "S"
    item.setLabel(edited, context: r.context)
    #expect(item.label?.size == "S" && item.label?.brand == "Zara" && item.tags.fit == .slim)
}

@MainActor @Test func S1B_I09_rescanReplacesLabelAndImage() async throws {
    let r = try Rig(); defer { r.cleanup() }
    await r.start(1)
    let id = try #require(r.model.photos.first).id
    let item = try #require(r.model.save(id, context: r.context))
    let old = Data("old".utf8)
    try r.store.save(old, named: ImageStore.labelName, for: item.id)
    let pipeline = LabelPipeline(scan: { _ in ("ZARA\nSize: M", nil) }, isBlurry: { _, _ in false })
    guard case .read(let data, let jpeg) = await pipeline.run(photo: photoData, box: nil, liveLines: [], liveBarcode: nil, pastBrands: []) else {
        Issue.record("expected a read"); return
    }
    item.replaceLabel(data, jpeg: jpeg, store: r.store, context: r.context)
    #expect(item.label?.brand == "Zara" && item.label?.size == "M")
    #expect(try r.store.load(ImageStore.labelName, for: item.id) != old)
}

@MainActor @Test func S1B_I10_blurryStillRejected() async throws {
    let r = try Rig(blurry: true); defer { r.cleanup() }
    await r.start(1)
    let id = try #require(r.model.photos.first).id
    let msg = await r.model.scanLabel(id, photo: photoData)
    #expect(msg == "Hold steady, it's blurry" && r.model.labelDraft == nil)
}

// MARK: Round 3 (S1B-I11...I13): AI category suggestion with a fake tagger, never the real model

private struct Boom: Error {}
private func tags(_ c: StyleEngine.Category, _ s: Subcategory) -> IdentityTags { IdentityTags(category: c, subcategory: s, styleOrigin: .western) }

@MainActor @Test func S1B_I11_aiAnswerPreselectedAndSavedAsAiRaw() async throws {
    let r = try Rig(tagger: FakeTagger(result: .success(tags(.top, .tshirt)))); defer { r.cleanup() }
    await r.start(1)
    let p = try #require(r.model.photos.first)
    let s = try #require(r.model.suggestion(p))
    #expect(s.title == "T-shirt · Top" && s.alternatives.count == 2 && !r.model.askCategory(p))
    let item = try #require(r.model.save(p.id, context: r.context))
    let raw = try #require(item.aiRawData.flatMap { try? JSONDecoder().decode(ItemTags.self, from: $0) })
    #expect(raw.category == .top && raw.subcategory == .tshirt && item.userOverridesData == nil)
    #expect(item.taggerVersion == "fake-1" && item.tags.category == .top)
    #expect(WardrobeView.sections(for: [item]).first?.title == "Top")
    let log = try #require(try r.logs().first { $0.purpose == "tagA" })
    #expect(try r.logs().count == 3 && log.purpose == "tagA" && log.success && log.model == "fake-1")
}

@MainActor @Test func S1B_I12_changingAnswerIsUserCorrection() async throws {
    let r = try Rig(tagger: FakeTagger(result: .success(tags(.top, .tshirt)))); defer { r.cleanup() }
    await r.start(1)
    let id = try #require(r.model.photos.first).id
    r.model.answerSubcategory(id, .polo)
    let item = try #require(r.model.save(id, context: r.context))
    let over = try #require(item.userOverridesData.flatMap { try? JSONDecoder().decode(ItemTags.self, from: $0) })
    let raw = try #require(item.aiRawData.flatMap { try? JSONDecoder().decode(ItemTags.self, from: $0) })
    #expect(over.subcategory == .polo && raw.subcategory == .tshirt && item.tags.subcategory == .polo)
}

@MainActor @Test func S1B_I12b_choosingTheAiAnswerAgainRemovesCorrection() async throws {
    let r = try Rig(tagger: FakeTagger(result: .success(tags(.top, .tshirt)))); defer { r.cleanup() }
    await r.start(1)
    let id = try #require(r.model.photos.first).id
    r.model.answerSubcategory(id, .polo); r.model.answerSubcategory(id, .tshirt)
    #expect(try #require(r.model.save(id, context: r.context)).userOverridesData == nil)
}

@MainActor @Test func S1B_I13_taggerThrowsFallsBackToFullLists() async throws {
    let r = try Rig(tagger: FakeTagger(result: .failure(Boom()))); defer { r.cleanup() }
    await r.start(1)
    let p = try #require(r.model.photos.first)
    #expect(r.model.suggestion(p) == nil && r.model.askCategory(p) && p.status == .ready)
    let logs = try r.logs()
    #expect(logs.count == 1 && logs[0].success == false && logs[0].purpose == "tagA")
    let item = try #require(r.model.save(p.id, context: r.context))
    #expect(item.aiRawData == nil && item.taggerVersion == nil)
}

@MainActor @Test func S1B_I15_boxGetsASecondUpscaledPass() async throws {
    nonisolated(unsafe) var sizes: [Int] = []
    let pipeline = LabelPipeline(scan: { img in sizes.append(img.width); return (sizes.count == 2 ? "WES\nSLIM FIT\n$" : "WES\nslim  fit", nil) },
                                 isBlurry: { _, _ in false })
    guard case .read(let d, _) = await pipeline.run(photo: photoData, box: CGRect(x: 0.1, y: 0.1, width: 0.5, height: 0.5), liveLines: ["Slim Fit"],
                                                    liveBarcode: nil, pastBrands: []) else { Issue.record("expected a read"); return }
    #expect(sizes.count == 4 && sizes[1] > sizes[0] / 2 && d.size == "S")   // still, 2x crop, stretched, inverted
    #expect(d.rawText == "Slim Fit\nWES\n$")
}

// MARK: Round 4 (S1B-I16...I18): Review again / Sort these, fakes only

@MainActor @Test func S1B_I16_reviewAgainUpdatesTheSameItem() async throws {
    let r = try Rig(); defer { r.cleanup() }
    await r.start(1)
    let firstID = try #require(r.model.photos.first).id
    let item = try #require(r.model.save(firstID, context: r.context))
    #expect(item.aiRawData == nil)
    let m = r.makeModel(tagger: FakeTagger(result: .success(tags(.top, .tshirt))))
    m.beginExisting([item]); await m.idle()
    let p = try #require(m.photos.first)
    #expect(p.existingID == item.id && m.suggestion(p)?.title == "T-shirt · Top")   // identity call ran: the item had no aiRaw
    m.answerCategory(p.id, .bottom); m.answerColor(p.id, .red)
    let saved = try #require(m.save(p.id, context: r.context))
    let n = try r.count()
    #expect(saved === item && saved.id == item.id && n == 1)
    #expect(item.tags.category == .bottom && item.colorNames.first == "red" && item.taggerVersion == "fake-1")
    let raw = try #require(item.aiRawData.flatMap { try? JSONDecoder().decode(ItemTags.self, from: $0) })
    #expect(raw.category == .top)
    #expect(try r.logs().count == 3)   // tagA, tagB, tagC
    #expect(FileManager.default.fileExists(atPath: r.store.url(for: ImageStore.originalName, id: item.id).path))
}

@MainActor @Test func S1B_I17_sortTheseOverUnsortedItems() async throws {
    let r = try Rig(); defer { r.cleanup() }
    await r.start(3)
    for p in r.model.photos { r.model.save(p.id, context: r.context) }
    let unsorted = WardrobeView.unsortedItems(try r.items())
    #expect(unsorted.count == 3)
    let m = r.makeModel()
    m.beginExisting(unsorted)
    #expect(m.unresolved.count == 3 && m.photos.count == 3)
    for p in m.photos { m.answerCategory(p.id, .top); m.save(p.id, context: r.context) }
    #expect(m.isFinished)
    #expect(WardrobeView.sections(for: try r.items()).map(\.title) == ["Top"])
    #expect(WardrobeView.unsortedItems(try r.items()).isEmpty)
}

@MainActor @Test func S1B_I18_retakeInReviewAgainKeepsLabelAndOverrides() async throws {
    let r = try Rig(); defer { r.cleanup() }
    await r.start(1)
    let id = try #require(r.model.photos.first).id
    await r.model.scanLabel(id, photo: photoData)
    r.model.confirmLabel(try #require(r.model.labelDraft).data)
    r.model.answerFit(id, .slim)
    let item = try #require(r.model.save(id, context: r.context))
    let before = try r.store.load(ImageStore.originalName, for: item.id)

    let m = r.makeModel()
    m.beginExisting([item])
    let pid = try #require(m.photos.first).id
    m.retake(pid)
    #expect(m.retakeID == pid && m.photo(pid)?.status == .ready)
    #expect(FileManager.default.fileExists(atPath: r.store.url(for: ImageStore.originalName, id: item.id).path))   // nothing deleted by retake
    await m.replace(pid, data: ImageCodec.jpegData(flat("CC3333", 300, 200))!, box: nil)
    #expect(m.photo(pid)?.processed?.itemID == item.id && m.retakeID == nil)
    let after = try r.store.load(ImageStore.originalName, for: item.id)
    #expect(after != before)
    #expect(FileManager.default.fileExists(atPath: r.store.url(for: ImageStore.labelName, id: item.id).path))
    #expect(try FileManager.default.contentsOfDirectory(atPath: r.store.root.path).count == 1)   // the temporary folder is gone
    let saved = try #require(m.save(pid, context: r.context))
    let n = try r.count()
    #expect(saved === item && n == 1 && saved.label?.brand == "Westside" && saved.tags.fit == .slim)
    #expect(try r.items().count == 1)
}
