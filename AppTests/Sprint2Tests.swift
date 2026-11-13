import CoreGraphics
import Foundation
import StyleEngine
import SwiftData
import Testing
import WardrobeImaging
@testable import AIStylist
@testable import WardrobeImaging

// Sprint 2 tagging half: queue, AI log, raw vs corrections, review chips, adjust cut-out, accuracy, delete all.
// Fake tagger and fake cut-out only: no real model, no Vision.

private func flat(_ hex: String, _ w: Int = 80, _ h: Int = 100) -> CGImage {
    let v = UInt32(hex, radix: 16) ?? 0
    let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setFillColor(red: CGFloat((v >> 16) & 255) / 255, green: CGFloat((v >> 8) & 255) / 255, blue: CGFloat(v & 255) / 255, alpha: 1)
    ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
    return ctx.makeImage()!
}
private let photoData = ImageCodec.jpegData(flat("336699", 300, 200))!

/// Cut-out fake with real instance masks: a red block left, a blue block right, so a re-cut has two candidates.
private struct TwoBlockCutout: CutoutProviding {
    func cutout(from image: CGImage, box: CGRect?) async throws -> CutoutResult {
        let w = 100, h = 100
        func rect(_ x0: Int, _ x1: Int, _ y0: Int, _ y1: Int) -> Mask {
            var px = [UInt8](repeating: 0, count: w * h)
            for y in y0..<y1 { for x in x0..<x1 { px[y * w + x] = 255 } }
            return Mask(width: w, height: h, pixels: px)
        }
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(red: 1, green: 1, blue: 1, alpha: 1); ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.setFillColor(red: 0.8, green: 0.1, blue: 0.1, alpha: 1); ctx.fill(CGRect(x: 5, y: 20, width: 40, height: 60))     // left (CG y up; masks are top-down, symmetric here)
        ctx.setFillColor(red: 0.1, green: 0.1, blue: 0.8, alpha: 1); ctx.fill(CGRect(x: 65, y: 40, width: 20, height: 30))
        let session = CutoutSession(image: ctx.makeImage()!, instances: [rect(5, 45, 20, 80), rect(65, 85, 30, 60)], box: nil)
        return try session.initial()
    }
}

@MainActor private struct Rig {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("s2-\(UUID().uuidString)")
    let store: ImageStore, container: ModelContainer
    var context: ModelContext { container.mainContext }
    init() throws {
        store = ImageStore(root: root.appendingPathComponent("items"))
        container = try ModelContainer(for: Schema(Item.allModels), configurations: ModelConfiguration(url: root.appendingPathComponent("t.store")))
    }
    func reopen() throws -> ModelContainer {
        try ModelContainer(for: Schema(Item.allModels), configurations: ModelConfiguration(url: root.appendingPathComponent("t.store")))
    }
    func queue(_ t: any ItemTagger, timeout: Duration = .seconds(30)) -> TaggingQueue {
        TaggingQueue(container: container, store: store, tagger: t, timeout: timeout, thermalOK: { true })
    }
    /// A saved item with a cut-out file and the given status.
    @discardableResult func item(_ status: ItemStatus = .tagging, hex: String = "B5522B") throws -> Item {
        let it = Item(originalFile: ImageStore.originalName, cutoutFile: ImageStore.cutoutName, displayFile: ImageStore.displayName)
        try store.save(ImageCodec.pngData(flat(hex))!, named: ImageStore.cutoutName, for: it.id)
        try store.save(photoData, named: ImageStore.originalName, for: it.id)
        try store.save(photoData, named: ImageStore.displayName, for: it.id)
        it.status = status; it.hexColors = [hex]; it.colorNames = ["rust"]
        context.insert(it); try context.save()
        return it
    }
    /// Fresh read from disk (the queue wrote through its own context).
    func fresh(_ id: UUID) throws -> Item { try fetch(id, in: ModelContext(container)) }
    func fetch(_ id: UUID, in c: ModelContext) throws -> Item {
        let target = id
        guard let it = try c.fetch(FetchDescriptor<Item>(predicate: #Predicate { $0.id == target })).first else { throw Missing() }
        return it
    }
    struct Missing: Error {}
    func logs() throws -> [AIRequestLog] { try ModelContext(container).fetch(FetchDescriptor<AIRequestLog>()).sorted { $0.createdAt < $1.createdAt } }
    func cleanup() { try? FileManager.default.removeItem(at: root) }
}
private func decode(_ d: Data?) -> ItemTags? { d.flatMap { try? JSONDecoder().decode(ItemTags.self, from: $0) } }

// MARK: raw vs corrections on Item (S2-U01...U07)

@MainActor @Test func S2_U05_editLeavesRawBytesIdentical() throws {
    let r = try Rig(); defer { r.cleanup() }
    let item = try r.item(.ready)
    var raw = ItemTags(); raw.fabric = .cotton; raw.category = .top
    item.replaceRaw(raw, version: "v1", context: r.context)
    let before = item.aiRawData
    item.setOverride(\.fabric, to: .linen, context: r.context)
    #expect(item.aiRawData == before && item.tags.fabric == .linen)
    item.setOverride(\.fabric, to: .cotton, context: r.context)   // the AI's own value: override removed, not stored
    #expect(item.userOverridesData == nil && item.tags.fabric == .cotton && item.aiRawData == before)
    item.setOverride(\.dressCodes, to: [], context: r.context)     // empty set rejected
    #expect(item.userOverridesData == nil)
}

@MainActor @Test func S2_U07_retagKeepsOverrides() throws {
    let r = try Rig(); defer { r.cleanup() }
    let item = try r.item(.ready)
    var raw = ItemTags(); raw.fabric = .cotton
    item.replaceRaw(raw, version: "v1", context: r.context)
    item.setOverride(\.fabric, to: .linen, context: r.context)
    var again = ItemTags(); again.fabric = .wool; again.pattern = .check
    item.replaceRaw(again, version: "v2", context: r.context)
    #expect(item.tags.fabric == .linen && item.tags.pattern == .check && item.taggerVersion == "v2")
    #expect(decode(item.aiRawData)?.fabric == .wool)
}

// MARK: AI log wrapper (S2-U21, U22)

@Test func S2_U21_rowOnSuccess() async throws {
    nonisolated(unsafe) var rows: [AICallRecord] = []
    let v = try await AICall.record(purpose: "tagA", model: "fake-1", tokens: { 7 }, sink: { rows.append($0) }) { 5 }
    #expect(v == 5 && rows.count == 1)
    #expect(rows[0].purpose == "tagA" && rows[0].provider == "onDevice" && rows[0].seconds > 0 && rows[0].success && rows[0].tokens == 7 && rows[0].error == nil)
}
@Test func S2_U22_rowOnFailureAndRethrow() async {
    nonisolated(unsafe) var rows: [AICallRecord] = []
    await #expect(throws: FakeTagger.Boom.self) {
        try await AICall.record(purpose: "tagB", model: "m", sink: { rows.append($0) }) { throw FakeTagger.Boom() } as Int
    }
    #expect(rows.count == 1 && !rows[0].success && rows[0].error?.isEmpty == false)
}

// MARK: queue (S2-U14...U20, U23, I02, I05)

@MainActor @Test func S2_U14_U16_U23_successPath() async throws {
    let r = try Rig(); defer { r.cleanup() }
    let item = try r.item(.tagging)
    let tagger = FakeTagger()
    let q = r.queue(tagger)
    await q.enqueue([item.id]); await q.waitUntilIdle()
    let it = try r.fresh(item.id)
    #expect(it.status == .ready && it.taggerVersion == tagger.version && it.lastError == nil)
    let raw = try #require(decode(it.aiRawData))
    #expect(raw.category == .top && raw.fabric == .cotton && raw.dressCodes == [.casual] && raw.caption == "A plain shirt")
    #expect(it.name == "Rust cotton shirt" && it.caption == "A plain shirt")
    #expect(try r.logs().map(\.purpose) == ["tagA", "tagB", "tagC"])
    #expect(try r.logs().allSatisfy { $0.success && $0.model == "fake-1" && $0.outputTokens == 42 })
}

@MainActor @Test func S2_U15_oneAtATime() async throws {
    let r = try Rig(); defer { r.cleanup() }
    let ids = try (0..<5).map { _ in try r.item(.tagging).id }
    let tagger = FakeTagger(); tagger.delay = .milliseconds(15)
    let q = r.queue(tagger)
    await q.enqueue(ids); await q.waitUntilIdle()
    #expect(tagger.maxRunning == 1 && tagger.identityCalls == 5)
    #expect(try ids.allSatisfy { try r.fresh($0).status == .ready })
}

@MainActor @Test func S2_U17_failurePath() async throws {
    let r = try Rig(); defer { r.cleanup() }
    let item = try r.item(.tagging)
    let tagger = FakeTagger(result: .failure(FakeTagger.Boom()))
    let q = r.queue(tagger)
    await q.enqueue([item.id]); await q.waitUntilIdle()
    let it = try r.fresh(item.id)
    #expect(it.status == .failed && it.lastError?.isEmpty == false && it.aiRawData == nil)
}

@MainActor @Test func S2_U18_manualRetry() async throws {
    let r = try Rig(); defer { r.cleanup() }
    let item = try r.item(.tagging)
    let tagger = FakeTagger(); tagger.failIdentityCalls = [1]
    let q = r.queue(tagger)
    await q.enqueue([item.id]); await q.waitUntilIdle()
    #expect(try r.fresh(item.id).status == .failed)
    await q.retry(item.id); await q.waitUntilIdle()
    let it = try r.fresh(item.id)
    #expect(it.status == .ready && it.lastError == nil && it.aiRawData != nil)
}

@MainActor @Test func S2_U19_resumeOnLaunch() async throws {
    let r = try Rig(); defer { r.cleanup() }
    let stuck = try [r.item(.tagging), r.item(.tagging)]
    let done = try r.item(.ready), failed = try r.item(.failed)
    let q = r.queue(FakeTagger())
    await q.start(); await q.waitUntilIdle()
    #expect(try stuck.allSatisfy { try r.fresh($0.id).status == .ready && r.fresh($0.id).aiRawData != nil })
    #expect(try r.fresh(done.id).aiRawData == nil && r.fresh(failed.id).status == .failed)   // ready and failed items are left alone
}

@MainActor @Test func S2_U20_timeoutThenMovesOn() async throws {
    let r = try Rig(); defer { r.cleanup() }
    let a = try r.item(.tagging), b = try r.item(.tagging)
    let tagger = FakeTagger(); tagger.hangOnIdentityCall = 1
    let q = r.queue(tagger, timeout: .milliseconds(200))
    await q.enqueue([a.id, b.id]); await q.waitUntilIdle()
    let fa = try r.fresh(a.id), fb = try r.fresh(b.id)
    #expect(fa.status == .failed && fa.lastError?.contains("Timed out") == true)
    #expect(fb.status == .ready)
}

@MainActor @Test func S2_I02_batchOfTenFourthFails() async throws {
    let r = try Rig(); defer { r.cleanup() }
    let ids = try (0..<10).map { _ in try r.item(.tagging).id }
    let tagger = FakeTagger(); tagger.failIdentityCalls = [4]
    let q = r.queue(tagger)
    await q.enqueue(ids); await q.waitUntilIdle()
    let statuses = try ids.map { try r.fresh($0).status }
    #expect(statuses.filter { $0 == .ready }.count == 9 && statuses.filter { $0 == .failed }.count == 1 && statuses[3] == .failed)
}

@MainActor @Test func S2_I05_restartMidQueue() async throws {
    let r = try Rig(); defer { r.cleanup() }
    let ids = try (0..<5).map { _ in try r.item(.tagging).id }
    let tagger = FakeTagger(); tagger.delay = .milliseconds(20)
    let q1 = r.queue(tagger)
    await q1.enqueue(ids)
    while try ids.filter({ try r.fresh($0).status == .ready }).count < 2 { try await Task.sleep(for: .milliseconds(10)) }
    await q1.stop()   // finishes the item in hand, leaves the rest as `tagging`
    await q1.waitUntilIdle()
    let doneBefore = try ids.filter { try r.fresh($0).status == .ready }.count
    #expect(doneBefore >= 2 && doneBefore < 5)
    let q2 = r.queue(tagger)   // "app restarted": a new queue on the same store
    await q2.start(); await q2.waitUntilIdle()
    #expect(try ids.allSatisfy { try r.fresh($0).status == .ready })
    #expect(tagger.identityCalls == 5)   // nothing tagged twice
}

@MainActor @Test func S2_U12_editedNameKeptOnRetag() async throws {
    let r = try Rig(); defer { r.cleanup() }
    let item = try r.item(.tagging)
    let q = r.queue(FakeTagger())
    await q.enqueue([item.id]); await q.waitUntilIdle()
    let auto = try r.fresh(item.id).name
    #expect(!auto.isEmpty)
    let c = ModelContext(r.container)   // user renames (separate context, saved)
    let again = try r.fetch(item.id, in: c)
    again.name = "My lucky shirt"; try c.save()
    await q.retry(item.id); await q.waitUntilIdle()
    #expect(try r.fresh(item.id).name == "My lucky shirt")
}

@MainActor @Test func S2_I04_unavailableThenTagUntagged() async throws {
    let r = try Rig(); defer { r.cleanup() }
    let a = try r.item(.ready), b = try r.item(.ready), tagged = try r.item(.ready)
    tagged.replaceRaw({ var t = ItemTags(); t.category = .top; return t }(), version: "x", context: r.context)
    let tagger = FakeTagger(); tagger.unavailableReason = "Apple Intelligence is turned off."
    let q = r.queue(tagger)
    #expect(await q.tagUntagged() == 0)   // model off: nothing is queued
    tagger.unavailableReason = nil
    #expect(await q.tagUntagged() == 2)
    await q.waitUntilIdle()
    #expect(try [a, b].allSatisfy { try r.fresh($0.id).status == .ready && r.fresh($0.id).aiRawData != nil })
    #expect(tagger.identityCalls == 2)
}

@MainActor @Test func S2_I06_coloursUntouchedByTagging() async throws {
    let r = try Rig(); defer { r.cleanup() }
    let item = try r.item(.tagging, hex: "4A5A3A")
    let q = r.queue(FakeTagger())
    await q.enqueue([item.id]); await q.waitUntilIdle()
    let it = try r.fresh(item.id)
    #expect(it.hexColors == ["4A5A3A"] && it.colorNames == ["rust"])
}

@MainActor @Test func S2_I03_editThenRetagSurvivesReopen() async throws {
    let r = try Rig(); defer { r.cleanup() }
    let item = try r.item(.tagging)
    let q = r.queue(FakeTagger())
    await q.enqueue([item.id]); await q.waitUntilIdle()
    let c = ModelContext(r.container)
    let it = try r.fetch(item.id, in: c)
    it.setOverride(\.fabric, to: .linen, context: c)
    let t2 = FakeTagger(version: "fake-2"); var newB = ItemTags(); newB.fabric = .wool; newB.pattern = .check; newB.fit = .slim; newB.length = .long; newB.collar = .polo; newB.sleeve = .short
    t2.constructionResult = newB
    let q2 = r.queue(t2)
    await q2.retry(item.id); await q2.waitUntilIdle()
    let reopened = ModelContext(try r.reopen())
    let again = try r.fetch(item.id, in: reopened)
    #expect(decode(again.aiRawData)?.fabric == .wool && again.tags.fabric == .linen && again.taggerVersion == "fake-2")
}

// MARK: review: pipeline, chips, queue hand-off (S2-I01, review chips)

@MainActor private func reviewModel(_ r: Rig, tagger: FakeTagger, queue: TaggingQueue? = nil, cutout: any CutoutProviding = TwoBlockCutout()) -> ReviewModel {
    let m = ReviewModel(processor: ItemImageProcessor(cutout: cutout, store: r.store), store: r.store, tagger: tagger, queue: queue,
                        scan: { _ in ("", nil) }, isBlurry: { _, _ in false })
    m.logContext = r.context
    return m
}

@MainActor @Test func S2_I01_onePhotoThroughWholePipeline() async throws {
    let r = try Rig(); defer { r.cleanup() }
    let m = reviewModel(r, tagger: FakeTagger())
    m.begin(count: 1) { _ in photoData }; await m.idle()
    let p = try #require(m.photos.first)
    let item = try #require(m.save(p.id, context: r.context))
    #expect(item.status == .ready && item.cutoutFile != nil && !item.hexColors.isEmpty)
    #expect(item.tags.category == .top && item.tags.fabric == .cotton && item.tags.dressCodes == [.casual] && item.taggerVersion == "fake-1")
    #expect(!item.name.isEmpty && item.caption == "A plain shirt")
    #expect(try r.logs().map(\.purpose) == ["tagA", "tagB", "tagC"])
    #expect(FileManager.default.fileExists(atPath: r.store.url(for: ImageStore.cutoutName, id: item.id).path))
}

@MainActor @Test func S2_review_footwearHasNoCollarOrSleeve() async throws {
    let r = try Rig(); defer { r.cleanup() }
    let t = FakeTagger(result: .success(IdentityTags(category: .footwear, subcategory: .sneakers, styleOrigin: .western)))
    var b = ItemTags(); b.fabric = .leather; b.closedToe = true; t.constructionResult = b
    let m = reviewModel(r, tagger: t)
    m.begin(count: 1) { _ in photoData }; await m.idle()
    let p = try #require(m.photos.first)
    let fields = m.chipFields(p)
    #expect(!fields.contains(.collar) && !fields.contains(.sleeve) && fields.contains(.closedToe) && fields.contains(.fabric))
    #expect(m.effectiveTags(p).collar == nil)
}

@MainActor @Test func S2_review_chipEditIsCorrectionOnly() async throws {
    let r = try Rig(); defer { r.cleanup() }
    let m = reviewModel(r, tagger: FakeTagger())
    m.begin(count: 1) { _ in photoData }; await m.idle()
    let id = try #require(m.photos.first).id
    m.setField(id, \.fabric, to: .linen)
    m.setField(id, \.dressCodes, to: [.festive, .party])
    m.setField(id, \.dressCodes, to: [])   // rejected
    #expect(m.effectiveTags(try #require(m.photo(id))).fabric == .linen)
    let item = try #require(m.save(id, context: r.context))
    #expect(decode(item.aiRawData)?.fabric == .cotton && decode(item.userOverridesData)?.fabric == .linen)
    #expect(item.tags.dressCodes == [.festive, .party] && decode(item.aiRawData)?.dressCodes == [.casual])
    m.setField(id, \.fabric, to: .cotton)   // AI's value again: not a correction (page is saved but model state still edits)
}

@MainActor @Test func S2_review_uncertainFieldsMarked() async throws {
    let r = try Rig(); defer { r.cleanup() }
    let t = FakeTagger(); var b = ItemTags(); b.fabric = .unknown; b.pattern = .solid; b.fit = .regular; b.length = .regular; b.sleeve = .long   // no collar answer
    t.constructionResult = b
    let m = reviewModel(r, tagger: t)
    m.begin(count: 1) { _ in photoData }; await m.idle()
    let p = try #require(m.photos.first)
    #expect(m.needsCheck(p, .fabric) && m.needsCheck(p, .collar) && !m.needsCheck(p, .pattern) && !m.needsCheck(p, .fit))
    m.setField(p.id, \.fabric, to: .linen)
    #expect(try !m.needsCheck(#require(m.photo(p.id)), .fabric))
}

@MainActor @Test func S2_review_saveBeforeTaggingFinishedHandsOffToQueue() async throws {
    let r = try Rig(); defer { r.cleanup() }
    let tagger = FakeTagger(); tagger.delay = .milliseconds(150)
    let q = r.queue(tagger)
    let m = reviewModel(r, tagger: tagger, queue: q)
    m.begin(count: 1) { _ in photoData }
    while m.photos.first?.processed == nil { try await Task.sleep(for: .milliseconds(5)) }
    let id = try #require(m.photos.first).id
    let item = try #require(m.save(id, context: r.context))   // tagging still running
    #expect(item.status == .tagging)
    await m.idle(); await q.waitUntilIdle()
    let it = try r.fresh(item.id)
    #expect(it.status == .ready && it.aiRawData != nil && it.name.isEmpty == false)
}

@MainActor @Test func S2_review_retagKeepsCorrections() async throws {
    let r = try Rig(); defer { r.cleanup() }
    let t = FakeTagger()
    let m = reviewModel(r, tagger: t)
    m.begin(count: 1) { _ in photoData }; await m.idle()
    let id = try #require(m.photos.first).id
    m.setField(id, \.fabric, to: .linen)
    var b = ItemTags(); b.fabric = .wool; b.pattern = .check; b.fit = .slim; b.length = .long; b.collar = .polo; b.sleeve = .short
    t.constructionResult = b
    m.retag(id); await m.idle()
    let p = try #require(m.photo(id))
    #expect(m.effectiveTags(p).fabric == .linen && m.effectiveTags(p).pattern == .check)
    #expect(try r.logs().count == 6)
}

// MARK: adjust cut-out (S2-U40...)

@MainActor @Test func S2_U40_choosingAnotherCandidateChangesSavedCutout() async throws {
    let r = try Rig(); defer { r.cleanup() }
    let m = reviewModel(r, tagger: FakeTagger())
    m.begin(count: 1) { _ in photoData }; await m.idle()
    let p = try #require(m.photos.first), pr = try #require(p.processed)
    let res = try #require(pr.cutoutResult)
    #expect(res.candidates.count == 2 && res.chosen.count == 1)
    let other = try #require(res.candidates.map(\.index).first { !res.chosen.contains($0) })
    let before = try r.store.load(ImageStore.cutoutName, for: pr.itemID)
    let beforeDisplay = try r.store.load(ImageStore.displayName, for: pr.itemID)
    nonisolated(unsafe) var notified: UUID?
    let token = NotificationCenter.default.addObserver(forName: .itemImagesChanged, object: nil, queue: .main) { notified = $0.object as? UUID }
    defer { NotificationCenter.default.removeObserver(token) }
    await m.recut(p.id, .chosen([other]))
    let after = try #require(m.photo(p.id)?.processed)
    #expect(after.cutoutResult?.chosen == [other])
    #expect(try r.store.load(ImageStore.cutoutName, for: pr.itemID) != before)      // the saved cut-out file changed
    #expect(try r.store.load(ImageStore.displayName, for: pr.itemID) != beforeDisplay)
    #expect(after.hexColors != pr.hexColors)                                           // colours follow the new cut-out
    #expect(notified == pr.itemID)                                                      // views showing these files are told to reload
    // a tap on the first block goes back
    await m.recut(p.id, .tap(CGPoint(x: 0.2, y: 0.5)))
    #expect(m.photo(p.id)?.processed?.cutoutResult?.chosen == res.chosen)
    let item = try #require(m.save(p.id, context: r.context))
    #expect(try r.store.load(ImageStore.cutoutName, for: item.id) == before)
}

@MainActor @Test func S2_U41_adjustOnSavedItemReRunsCutoutThenAppliesChoice() async throws {
    let r = try Rig(); defer { r.cleanup() }
    let first = reviewModel(r, tagger: FakeTagger())
    first.begin(count: 1) { _ in photoData }; await first.idle()
    let firstID = try #require(first.photos.first).id
    let item = try #require(first.save(firstID, context: r.context))
    let before = try r.store.load(ImageStore.cutoutName, for: item.id)
    let m = reviewModel(r, tagger: FakeTagger())
    m.beginExisting([item]); await m.idle()
    let id = try #require(m.photos.first).id
    #expect(m.photo(id)?.processed?.cutoutResult == nil)
    await m.prepareAdjust(id)
    let res = try #require(m.photo(id)?.processed?.cutoutResult)
    #expect(res.candidates.count == 2)
    let other = try #require(res.candidates.map(\.index).first { !res.chosen.contains($0) })
    await m.recut(id, .chosen([other]))
    m.save(id, context: r.context)
    #expect(try r.store.load(ImageStore.cutoutName, for: item.id) != before)
}

// MARK: adjust cut-out box and Apply feedback (S2-I20, S2-I21)

@MainActor @Test func S2_I20_applyingABoxUpdatesSavedCutoutAndNotifies() async throws {
    let r = try Rig(); defer { r.cleanup() }
    let m = reviewModel(r, tagger: FakeTagger())
    m.begin(count: 1) { _ in photoData }; await m.idle()
    let p = try #require(m.photos.first), pr = try #require(p.processed)
    let res = try #require(pr.cutoutResult)
    let other = try #require(res.candidates.map(\.index).first { !res.chosen.contains($0) })
    let ob = try #require(res.candidates.first { $0.index == other }).bounds
    let before = try r.store.load(ImageStore.cutoutName, for: pr.itemID)
    nonisolated(unsafe) var notified: UUID?
    let token = NotificationCenter.default.addObserver(forName: .itemImagesChanged, object: nil, queue: .main) { notified = $0.object as? UUID }
    defer { NotificationCenter.default.removeObserver(token) }
    let ok = await m.recut(p.id, .box(ob.insetBy(dx: -0.02, dy: -0.02), chosen: nil))
    #expect(ok)
    #expect(m.photo(p.id)?.processed?.cutoutResult?.chosen == [other])
    #expect(try r.store.load(ImageStore.cutoutName, for: pr.itemID) != before)
    #expect(notified == pr.itemID)
    // an empty box: inline error, files untouched, Apply reports failure so the sheet stays open
    let saved = try r.store.load(ImageStore.cutoutName, for: pr.itemID)
    nonisolated(unsafe) var again = false
    let t2 = NotificationCenter.default.addObserver(forName: .itemImagesChanged, object: nil, queue: .main) { _ in again = true }
    defer { NotificationCenter.default.removeObserver(t2) }
    let bad = await m.recut(p.id, .box(CGRect(x: 0.45, y: 0.0, width: 0.1, height: 0.1), chosen: nil))
    #expect(!bad && m.photo(p.id)?.error?.contains("box") == true && !again)
    #expect(try r.store.load(ImageStore.cutoutName, for: pr.itemID) == saved)
}

// Austin's phone: Apply did nothing and said nothing. recut returned silently when the photo had no stored masks
// (saved item whose re-run failed) and the sheet dismissed whatever happened, hiding any error.
@MainActor @Test func S2_I21_applyAlwaysReportsAFailure() async throws {
    let r = try Rig(); defer { r.cleanup() }
    let first = reviewModel(r, tagger: FakeTagger())
    first.begin(count: 1) { _ in photoData }; await first.idle()
    let fid0 = try #require(first.photos.first).id
    let item = try #require(first.save(fid0, context: r.context))
    let m = reviewModel(r, tagger: FakeTagger())
    m.beginExisting([item]); await m.idle()
    let id = try #require(m.photos.first).id
    #expect(m.photo(id)?.processed?.cutoutResult == nil)              // saved earlier: no stored masks yet
    let ok = await m.recut(id, .chosen([0]))
    #expect(!ok && m.photo(id)?.error != nil)
    // a fake result (no stored masks) fails loudly too
    let fake = reviewModel(r, tagger: FakeTagger(), cutout: NoSessionCutout())
    fake.begin(count: 1) { _ in photoData }; await fake.idle()
    let fid = try #require(fake.photos.first).id
    let ok2 = await fake.recut(fid, .chosen([0]))
    #expect(!ok2 && fake.photo(fid)?.error != nil)
}

private struct NoSessionCutout: CutoutProviding {
    func cutout(from image: CGImage, box: CGRect?) async throws -> CutoutResult {
        CutoutResult(cutout: flat("112233", 40, 40), mask: Mask(width: 4, height: 4, pixels: [UInt8](repeating: 255, count: 16)))
    }
}

// MARK: delete all data, status text

@MainActor @Test func S2_settings_deleteAllRemovesEverything() async throws {
    let r = try Rig(); defer { r.cleanup() }
    try r.item(.ready); try r.item(.ready)
    r.context.insert(Outfit(name: "o", source: .manual))
    r.context.insert(AIRequestLog(purpose: "tagA", provider: "onDevice", model: "m", durationSeconds: 1, success: true))
    try r.context.save()
    let counts = DataReset.counts(in: r.context)
    #expect(counts.items == 2 && counts.outfits == 1 && counts.aiLogs == 1)
    #expect(counts.summary.contains("2 items") && counts.summary.contains("1 outfit"))
    DataReset.deleteAll(in: r.context, store: r.store)
    #expect(DataReset.counts(in: r.context) == .init(items: 0, outfits: 0, wearLogs: 0, aiLogs: 0, feedback: 0))
    #expect(!FileManager.default.fileExists(atPath: r.store.root.path))
}

@Test func S2_U29_availabilityMapping() {
    #expect(AIStatus.describe(reason: nil).banner == nil && AIStatus.describe(reason: nil).manualMode == false)
    let off = AIStatus.describe(reason: "Apple Intelligence is turned off in Settings.")
    #expect(off.banner?.contains("turned off") == true && off.manualMode)
}

@MainActor @Test func S2_accuracy_fromItems() throws {
    let r = try Rig(); defer { r.cleanup() }
    let item = try r.item(.ready)
    var raw = ItemTags(); raw.category = .top; raw.fabric = .cotton
    item.replaceRaw(raw, version: "v", context: r.context)
    item.setOverride(\.fabric, to: .linen, context: r.context)
    let untagged = try r.item(.ready)
    let rep = AccuracyModel.report(for: [item, untagged])
    #expect(rep.itemCount == 1 && rep.accuracy("fabric") == 0 && rep.accuracy("category") == 100)
}
