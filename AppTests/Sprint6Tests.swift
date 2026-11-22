import CoreGraphics
import Foundation
import StyleEngine
import SwiftData
import Testing
import WardrobeImaging
@testable import AIStylist

// Sprint 6 app-side tests (SPRINT_6_TESTS.md). Fakes only: no Vision, no real model, no network.

private struct FlatCutout: CutoutProviding {
    func cutout(from image: CGImage, box: CGRect?) async throws -> CutoutResult {
        CutoutResult(cutout: flat("336699"), mask: Mask(width: 20, height: 20, pixels: [UInt8](repeating: 255, count: 400)))
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

/// Every photo gets the same print; distance comes from a table keyed by the stored print data.
private struct FakePrints: FeaturePrinting {
    var print = Data("new".utf8)
    var distances: [Data: Double] = [:]
    func compute(from image: CGImage) -> Data? { print }
    func distance(_ a: Data, _ b: Data) -> Double? { distances[b] }
}

@MainActor private struct Rig {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("s6-\(UUID().uuidString)")
    let store: ImageStore, container: ModelContainer
    var context: ModelContext { container.mainContext }
    init() throws {
        store = ImageStore(root: root.appendingPathComponent("items"))
        container = try ModelContainer(for: Schema(Item.allModels), configurations: ModelConfiguration(url: root.appendingPathComponent("t.store")))
    }
    func model(prints: FakePrints = FakePrints()) -> ReviewModel {
        let m = ReviewModel(processor: ItemImageProcessor(cutout: FlatCutout(), store: store), store: store, prints: prints,
                            scan: { _ in ("", nil) }, isBlurry: { _, _ in false })
        m.logContext = context
        return m
    }
    @discardableResult func existing(_ name: String, print: Data?, sub: Subcategory = .shirt) -> Item {
        let i = Item(originalFile: "original.jpg", cutoutFile: nil, displayFile: "display.jpg")
        var t = ItemTags(); t.category = .top; t.subcategory = sub
        i.aiRawData = try? JSONEncoder().encode(t); i.name = name; i.status = .ready; i.featurePrintData = print
        context.insert(i); try? context.save()
        return i
    }
    func cleanup() { try? FileManager.default.removeItem(at: root) }
}

@MainActor private func add(_ m: ReviewModel) async -> UUID {
    m.begin(count: 1) { _ in photoData }
    await m.idle()
    return m.photos.last!.id
}

// MARK: Duplicate flow (S6-I01)

@MainActor @Test func S6_I01_nearIdenticalPhotoRaisesThePrompt() async throws {
    let r = try Rig(); defer { r.cleanup() }
    let old = Data("old".utf8)
    let shirt = r.existing("Rust shirt", print: old)
    let m = r.model(prints: FakePrints(distances: [old: 0.12]))
    let id = await add(m)
    let offer = try #require(m.photo(id)?.duplicate)
    #expect(offer.itemID == shirt.id && offer.name == "Rust shirt")
}

@MainActor @Test func S6_I01_farPhotoAndPrintlessItemsRaiseNothing() async throws {
    let r = try Rig(); defer { r.cleanup() }
    let old = Data("old".utf8)
    r.existing("Far shirt", print: old)
    r.existing("Old shirt without a print", print: nil)
    let m = r.model(prints: FakePrints(distances: [old: 1.4]))
    let id = await add(m)
    #expect(m.photo(id)?.duplicate == nil)
}

@MainActor @Test func S6_I01_sameDiscardsTheNewPhotoAndKeepsOneItem() async throws {
    let r = try Rig(); defer { r.cleanup() }
    let old = Data("old".utf8)
    r.existing("Rust shirt", print: old)
    let m = r.model(prints: FakePrints(distances: [old: 0.1]))
    let id = await add(m)
    let newItem = try #require(m.photo(id)?.processed).itemID
    m.discardAsDuplicate(id)
    #expect(m.photo(id)?.status == .discarded)
    #expect(try r.context.fetchCount(FetchDescriptor<Item>()) == 1)
    #expect(!FileManager.default.fileExists(atPath: r.store.folder(for: newItem).path))
}

@MainActor @Test func S6_I01_differentKeepsBothAndStoresThePrint() async throws {
    let r = try Rig(); defer { r.cleanup() }
    let old = Data("old".utf8)
    r.existing("Rust shirt", print: old)
    let m = r.model(prints: FakePrints(print: Data("fresh".utf8), distances: [old: 0.1]))
    let id = await add(m)
    m.keepBoth(id)
    #expect(m.photo(id)?.duplicate == nil)
    let saved = try #require(m.save(id, context: r.context))
    #expect(try r.context.fetchCount(FetchDescriptor<Item>()) == 2)
    #expect(saved.featurePrintData == Data("fresh".utf8))
}

@MainActor @Test func S6_I01_otherSubcategoryIsNotOffered() async throws {
    let r = try Rig(); defer { r.cleanup() }
    let old = Data("old".utf8)
    r.existing("Black chinos", print: old, sub: .chinos)
    let tagger = FakeTagger()                                   // identity answers: a shirt
    let m = ReviewModel(processor: ItemImageProcessor(cutout: FlatCutout(), store: r.store), store: r.store, tagger: tagger,
                        prints: FakePrints(distances: [old: 0.05]), scan: { _ in ("", nil) }, isBlurry: { _, _ in false })
    m.logContext = r.context
    let id = await add(m)
    #expect(m.photo(id)?.duplicate == nil)
}

// MARK: Weather fills the default (S6-I02, S6-U10)

private final class StubWeather: WeatherSource, @unchecked Sendable {
    var result: Result<WeatherSnapshot, Error>
    init(max: Double? = nil, rain: Double = 0) {
        result = max.map { .success(WeatherSnapshot(feelsLikeMax: $0, feelsLikeMin: $0 - 6, rainChance: rain)) } ?? .failure(Boom())
    }
    struct Boom: Error {}
    func location() async -> (lat: Double, lon: Double)? { (12.9, 77.6) }
    func snapshot(lat: Double, lon: Double) async throws -> WeatherSnapshot { try result.get() }
}

@MainActor private func stylist(weather: StubWeather, parser: FakeIntentParser, in r: Rig) -> StylistViewModel {
    StylistViewModel(parser: parser, writer: FakeNoteWriter(), context: r.context, store: r.store, today: .now,
                     weather: TodaysWeather(source: weather))
}

@MainActor @Test func S6_I02_weatherFillsTheDefaultWhenTheMessageHasNone() async throws {
    let r = try Rig(); defer { r.cleanup() }
    let vm = stylist(weather: StubWeather(max: 36), parser: FakeIntentParser(.success(OccasionIntent(occasion: .casualDay))), in: r)
    await vm.refreshWeather()
    await vm.send("something for lunch")
    #expect(vm.intent?.weatherFeel == .hot)
}

@MainActor @Test func S6_U10_theUsersWordsWin() async throws {
    let r = try Rig(); defer { r.cleanup() }
    let cold = OccasionIntent(occasion: .office, weatherFeel: .cold)
    let vm = stylist(weather: StubWeather(max: 36), parser: FakeIntentParser(.success(cold)), in: r)
    await vm.refreshWeather()
    await vm.send("it's cold in the office")
    #expect(vm.intent?.weatherFeel == .cold)
}

@MainActor @Test func S6_I02_occasionChipGetsTodaysWeatherToo() async throws {
    let r = try Rig(); defer { r.cleanup() }
    let vm = stylist(weather: StubWeather(max: 12), parser: FakeIntentParser(), in: r)
    await vm.refreshWeather()
    vm.choose(.office)
    #expect(vm.intent?.weatherFeel == .cold)
}

@MainActor @Test func S6_I02_aFailedWeatherRequestChangesNothing() async throws {
    let r = try Rig(); defer { r.cleanup() }
    let vm = stylist(weather: StubWeather(), parser: FakeIntentParser(.success(OccasionIntent(occasion: .casualDay))), in: r)
    await vm.refreshWeather()
    await vm.send("lunch")
    #expect(vm.intent?.weatherFeel == WeatherFeel.unknown)
    #expect(vm.intent?.occasion == .casualDay)
}

@MainActor @Test func S6_I02_aChipEditToAnyWeatherSticks() async throws {
    let r = try Rig(); defer { r.cleanup() }
    let vm = stylist(weather: StubWeather(max: 36), parser: FakeIntentParser(.success(OccasionIntent(occasion: .casualDay))), in: r)
    await vm.refreshWeather()
    await vm.send("lunch")
    vm.edit { $0.weatherFeel = .unknown }
    #expect(vm.intent?.weatherFeel == WeatherFeel.unknown)
}

// MARK: Metrics from the store (S6-I04, app side)

@MainActor @Test func S6_I04_savingARoutineItemStampsReadyAt() async throws {
    let r = try Rig(); defer { r.cleanup() }
    let m = r.model()                                   // no tagger: the item is ready on save
    let id = await add(m)
    let item = try #require(m.save(id, context: r.context))
    let ready = try #require(item.readyAt)
    #expect(ready >= item.createdAt && ready.timeIntervalSince(item.createdAt) < 60)
}

@MainActor @Test func S6_I04_reportComesFromTheStore() async throws {
    let r = try Rig(); defer { r.cleanup() }
    let a = r.existing("A", print: nil), b = r.existing("B", print: nil)
    a.setOverride(\.fabric, to: .linen, context: r.context)
    var raw = ItemTags(); raw.category = .top; raw.subcategory = .shirt; raw.fabric = .cotton
    a.replaceRaw(raw, version: "v", context: r.context); b.replaceRaw(raw, version: "v", context: r.context)
    a.setOverride(\.fabric, to: .linen, context: r.context)
    b.cutoutFailed = true
    r.context.insert(AIRequestLog(purpose: "intent", provider: "onDevice", model: "m", durationSeconds: 3, success: true))
    r.context.insert(FeedbackEvent(outfitId: UUID(), action: "saved"))
    try r.context.save()
    let report = MVPMetricsModel.report(in: r.context)
    #expect(report.itemCount == 2)
    #expect(report.editsPerItemMedian == 0.5)           // one item with 1 override, one with none
    #expect(report.cutoutSuccessPercent == 50)
    #expect(report.intentMedianSeconds == 3)
    #expect(report.saved == 1)
    #expect(report.paidProviderUsed == false)
    #expect(MVPMetricsModel.markdown(in: r.context).contains("Edits per item"))
}

@MainActor @Test func S6_I04_queueStampsReadyAtWhenTaggingFinishes() async throws {
    let r = try Rig(); defer { r.cleanup() }
    let it = Item(originalFile: ImageStore.originalName, cutoutFile: ImageStore.cutoutName, displayFile: ImageStore.displayName)
    try r.store.save(ImageCodec.pngData(flat("B5522B"))!, named: ImageStore.cutoutName, for: it.id)
    it.status = .tagging
    r.context.insert(it); try r.context.save()
    #expect(it.readyAt == nil)
    let q = TaggingQueue(container: r.container, store: r.store, tagger: FakeTagger(), timeout: .seconds(30), thermalOK: { true })
    await q.enqueue([it.id]); await q.waitUntilIdle()
    let id = it.id
    let fresh = try #require(try ModelContext(r.container).fetch(FetchDescriptor<Item>(predicate: #Predicate { $0.id == id })).first)
    #expect(fresh.status == .ready)
    #expect(fresh.readyAt != nil)
}

// MARK: Adding from a category page (preset category)

@MainActor private func presetModel(_ r: Rig, preset: StyleEngine.Category?, tagger: (any ItemTagger)?) -> ReviewModel {
    let m = ReviewModel(processor: ItemImageProcessor(cutout: FlatCutout(), store: r.store), store: r.store, tagger: tagger,
                        presetCategory: preset, scan: { _ in ("", nil) }, isBlurry: { _, _ in false })
    m.logContext = r.context
    return m
}

@MainActor @Test func S6_preset_categoryWinsOverADifferentAIAnswerAndIsFlagged() async throws {
    let r = try Rig(); defer { r.cleanup() }
    let m = presetModel(r, preset: .bottom, tagger: FakeTagger())            // the AI says: shirt, a top
    let id = await add(m)
    let p = try #require(m.photo(id))
    #expect(m.effectiveCategory(p) == .bottom)
    #expect(m.effectiveSubcategory(p) == nil)                                // the AI's "shirt" is not a bottom
    #expect(m.needsSubcategory(p))
    let note = try #require(m.categoryNote(p))
    #expect(note.lowercased().contains("top") && note.lowercased().contains("bottom"))
    m.answerSubcategory(id, .chinos)
    #expect(m.needsSubcategory(try #require(m.photo(id))) == false)
    let item = try #require(m.save(id, context: r.context))
    #expect(item.tags.category == .bottom)
    #expect(item.tags.subcategory == .chinos)
    #expect(item.aiRaw.category == .top)                                     // the AI's answer is kept as it was
    #expect(item.userOverrides.category == .bottom)                          // and the correction is recorded
}

@MainActor @Test func S6_preset_whenTheAIAgreesNothingIsOverriddenAndNothingFlagged() async throws {
    let r = try Rig(); defer { r.cleanup() }
    let m = presetModel(r, preset: .top, tagger: FakeTagger())               // the AI says: shirt, a top
    let id = await add(m)
    let p = try #require(m.photo(id))
    #expect(m.effectiveCategory(p) == .top && m.effectiveSubcategory(p) == .shirt)
    #expect(m.categoryNote(p) == nil && m.needsSubcategory(p) == false)
    let item = try #require(m.save(id, context: r.context))
    #expect(item.userOverrides.category == nil)
    #expect(item.tags.category == .top)
}

@MainActor @Test func S6_preset_worksWithTheAIOff() async throws {
    let r = try Rig(); defer { r.cleanup() }
    let m = presetModel(r, preset: .footwear, tagger: nil)
    let id = await add(m)
    let p = try #require(m.photo(id))
    #expect(m.effectiveCategory(p) == .footwear)
    #expect(m.askCategory(p) == false)
    #expect(m.needsSubcategory(p))                                           // nothing named the kind of footwear yet
    m.answerSubcategory(id, .loafers)
    let item = try #require(m.save(id, context: r.context))
    #expect(item.tags.category == .footwear && item.tags.subcategory == .loafers)
}

@MainActor @Test func S6_noPreset_behavesAsBefore() async throws {
    let r = try Rig(); defer { r.cleanup() }
    let m = presetModel(r, preset: nil, tagger: FakeTagger())
    let id = await add(m)
    let p = try #require(m.photo(id))
    #expect(m.effectiveCategory(p) == .top && m.categoryNote(p) == nil && m.needsSubcategory(p) == false)
}
