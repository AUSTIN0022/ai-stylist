import CoreGraphics
import Foundation
import StyleEngine
import SwiftData
import Testing
import WardrobeImaging
@testable import AIStylist

// Sprint 5 app-side tests (SPRINT_5_TESTS.md). Fakes only: the real model is never called here.

private let day: TimeInterval = 86_400
private let festival = OccasionIntent(occasion: .festival, timeOfDay: .evening, setting: .indoor)

@MainActor private struct Rig {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("s5-\(UUID().uuidString)")
    let store: ImageStore
    var container: ModelContainer
    var context: ModelContext { container.mainContext }
    init() throws {
        store = ImageStore(root: root.appendingPathComponent("items"))
        container = try ModelContainer(for: Schema(Item.allModels), configurations: ModelConfiguration(url: root.appendingPathComponent("t.store")))
    }
    func reopen() throws -> ModelContainer {
        try ModelContainer(for: Schema(Item.allModels), configurations: ModelConfiguration(url: root.appendingPathComponent("t.store")))
    }
    func cleanup() { try? FileManager.default.removeItem(at: root) }

    @discardableResult
    func make(_ name: String, _ cat: StyleEngine.Category, _ sub: Subcategory, _ colour: ColorName,
              dc: [DressCode] = [.smartCasual], origin: StyleOrigin = .western) -> Item {
        let i = Item(originalFile: "original.jpg", cutoutFile: "cutout.png", displayFile: "display.jpg")
        var t = ItemTags(); t.category = cat; t.subcategory = sub; t.styleOrigin = origin; t.pattern = .solid
        t.dressCodes = dc; t.formality = 3; t.seasons = [.summer, .monsoon, .winter]; t.warmth = 1; t.statement = .plain
        if cat == .footwear { t.closedToe = true }
        i.aiRawData = try? JSONEncoder().encode(t); i.name = name; i.colorNames = [colour.rawValue]; i.status = .ready
        context.insert(i); try? context.save()
        return i
    }

    /// 4 tops, 4 bottoms, 3 shoes that all pass a smart-casual festival evening.
    @discardableResult func seed() -> [Item] {
        [make("Rust shirt", .top, .shirt, .rust), make("Cream shirt", .top, .shirt, .cream),
         make("Olive polo", .top, .polo, .olive), make("White tee", .top, .tshirt, .white),
         make("Black chinos", .bottom, .chinos, .black), make("Navy trousers", .bottom, .trousers, .navy),
         make("Beige chinos", .bottom, .chinos, .beige), make("Grey trousers", .bottom, .trousers, .grey),
         make("White sneakers", .footwear, .sneakers, .white), make("Black loafers", .footwear, .loafers, .black),
         make("Brown loafers", .footwear, .loafers, .brown)]
    }
    func items() -> [Item] { (try? context.fetch(FetchDescriptor<Item>())) ?? [] }
    func vm(today: Date = .now) -> StylistViewModel {
        StylistViewModel(parser: FakeIntentParser(), writer: FakeNoteWriter(), context: context, store: store, today: today)
    }
}

private func count<T: PersistentModel>(_ c: ModelContext, _ t: T.Type) -> Int { (try? c.fetchCount(FetchDescriptor<T>())) ?? -1 }

// MARK: Manual outfits (I01, I06, I07)

@MainActor @Test func S5_I01_manualOutfitEndToEnd() throws {
    var r = try Rig(); defer { r.cleanup() }
    let all = r.seed()
    let (shirt, chinos, shoes) = (all[0], all[4], all[9])
    var canvas = OutfitCanvas()
    let wardrobe = all.map(\.engineItem)
    for i in [shirt, chinos, shoes] { canvas.add(i.engineItem, using: wardrobe) }
    canvas.move(shirt.id, by: CGSize(width: 37, height: -12), in: CGSize(width: 390, height: 480))
    canvas.scale(chinos.id, to: 1.7)
    let saved = OutfitSaver.saveManual(canvas, name: "Mine", occasion: .festival, editing: nil, in: r.context)
    let id = saved.id
    let want = Set([shirt.id, chinos.id, shoes.id])

    r.container = try r.reopen()
    let o = try #require(try r.context.fetch(FetchDescriptor<Outfit>(predicate: #Predicate { $0.id == id })).first)
    #expect(o.source == OutfitSource.manual)
    #expect(o.saved)
    #expect(o.name == "Mine")
    #expect(o.occasion == "festival")
    let rows = try r.context.fetch(FetchDescriptor<OutfitItem>()).filter { $0.outfitId == id }
    #expect(Set(rows.map(\.itemId)) == want)
    #expect(Set(rows.map(\.slot)) == ["top", "bottom", "footwear"])
    let back = try #require(o.canvas)
    for p in canvas.items {
        let q = try #require(back.items.first { $0.itemId == p.itemId })
        #expect(abs(q.x - p.x) < 1e-6)
        #expect(abs(q.y - p.y) < 1e-6)
        #expect(abs(q.scale - p.scale) < 1e-6)
        #expect(q.z == p.z)
    }
}

@MainActor @Test func S5_I06_aiOutfitOpenedInBuilder() throws {
    let r = try Rig(); defer { r.cleanup() }
    let all = r.seed()
    let slots: [Slot: UUID] = [.top: all[0].id, .bottom: all[4].id, .footwear: all[9].id]
    let ai = OutfitSaver.save(id: UUID(), slots: slots, occasion: .festival, note: nil, in: r.context)
    let rows = try r.context.fetch(FetchDescriptor<OutfitItem>())
    var canvas = OutfitSaver.canvas(for: ai, rows: rows)
    #expect(canvas == OutfitCanvas(slots: slots))
    canvas.moveTo(all[0].id, x: 0.3, y: 0.3)
    let edited = OutfitSaver.saveManual(canvas, name: nil, occasion: nil, editing: ai, in: r.context)
    #expect(edited.id == ai.id && edited.source == .ai)
    #expect(count(r.context, Outfit.self) == 1)
    let p = try #require(edited.canvas?.items.first { $0.itemId == all[0].id })
    #expect(abs(p.x - 0.3) < 1e-9 && abs(p.y - 0.3) < 1e-9)
    #expect(OutfitSaver.canvas(for: edited, rows: try r.context.fetch(FetchDescriptor<OutfitItem>())) == canvas)
}

@MainActor @Test func S5_I07_manualOutfitCountsAsFeedback() throws {
    let r = try Rig(); defer { r.cleanup() }
    let all = r.seed()
    var canvas = OutfitCanvas()
    for i in [all[1], all[5]] { canvas.add(i.engineItem, using: all.map(\.engineItem)) }
    let o = OutfitSaver.saveManual(canvas, name: nil, occasion: nil, editing: nil, in: r.context)
    let events = try r.context.fetch(FetchDescriptor<FeedbackEvent>())
    #expect(events.count == 1 && events[0].action == "saved" && events[0].outfitId == o.id)
    let want: [UUID] = [all[1].id, all[5].id].sorted { $0.uuidString < $1.uuidString }
    let expected: [LearningEvent] = [LearningEvent.saved(want)]
    #expect(Learning.events(in: r.context) == expected)
}

@MainActor @Test func S5_manualOutfitNeedsTwoItems() throws {
    let r = try Rig(); defer { r.cleanup() }
    let all = r.seed()
    var canvas = OutfitCanvas()
    canvas.add(all[0].engineItem, using: all.map(\.engineItem))
    #expect(!OutfitSaver.canSave(canvas))
    canvas.add(all[4].engineItem, using: all.map(\.engineItem))
    #expect(OutfitSaver.canSave(canvas))
}

// MARK: Wear log (U08, U09, I02)

@MainActor @Test func S5_U08_markWorn() throws {
    let r = try Rig(); defer { r.cleanup() }
    let all = r.seed()
    let ids = [all[0].id, all[4].id], oid = UUID(), d = Date(timeIntervalSince1970: 1_800_000_000)
    WearLogger.markWorn(itemIds: ids, outfitId: oid, on: d, in: r.context)
    let logs = try r.context.fetch(FetchDescriptor<WearLog>())
    #expect(logs.count == 1)
    #expect(logs[0].outfitId == oid)
    #expect(Set(logs[0].itemIds) == Set(ids))
    #expect(logs[0].date == d)
    #expect(all[0].lastWornAt == d)
    #expect(all[4].lastWornAt == d)
    #expect(all[1].lastWornAt == nil)
    #expect(all[0].wearCount(in: r.context) == 1 && all[1].wearCount(in: r.context) == 0)
}

@MainActor @Test func S5_U09_backdatedWearKeepsLaterDate() throws {
    let r = try Rig(); defer { r.cleanup() }
    let all = r.seed()
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    WearLogger.markWorn(itemIds: [all[0].id], outfitId: nil, on: now, in: r.context)
    WearLogger.markWorn(itemIds: [all[0].id], outfitId: nil, on: now.addingTimeInterval(-7 * day), in: r.context)
    #expect(all[0].lastWornAt == now && all[0].wearCount(in: r.context) == 2)
}

@MainActor @Test func S5_I02_wornTodaySkippedTomorrow() async throws {
    let r = try Rig(); defer { r.cleanup() }
    r.seed()
    let d = Date(timeIntervalSince1970: 1_800_000_000)
    let first = r.vm(today: d)
    defer { _ = 0 }
    first.choose(.festival)
    let top = try #require(first.outfits.first)
    let wornKey = top.candidate.key
    WearLogger.markWorn(itemIds: top.candidate.itemIds, outfitId: top.id, on: d, in: r.context)

    let next = r.vm(today: d.addingTimeInterval(day))
    next.choose(.festival)
    #expect(next.outfits.count == 3)
    #expect(!next.outfits.contains { $0.candidate.key == wornKey })

    await first.notesTask?.value; await next.notesTask?.value
    let later = OutfitEngine.generate(intent: festival, items: r.items().map(\.engineItem), context: EngineContext(today: d.addingTimeInterval(5 * day)))
    for id in wornKey.ids { #expect(later.rejected[id] != .wornRecently) }
}

// MARK: Learning (I03, stylist events)

@MainActor @Test func S5_I03_learningChangesRanking() throws {
    let r = try Rig(); defer { r.cleanup() }
    let all = r.seed()
    let (rust, black, grey) = (all[0], all[4], all[7])
    let twin = r.make("Black chinos 2", .bottom, .chinos, .black)      // identical to `black` in every tag
    // A+B (rust shirt + black chinos) saved in three different outfits.
    for shoe in [all[8], all[9], all[10]] {
        OutfitSaver.save(id: UUID(), slots: [.top: rust.id, .bottom: black.id, .footwear: shoe.id], occasion: nil, note: nil, in: r.context)
    }
    #expect(count(r.context, Outfit.self) == 3)
    let ws = Learning.pairWeights(in: r.context)
    #expect(abs(PairWeights.value(ws, rust.id, black.id) - 0.8) < 1e-9)
    let base = OutfitCandidate(slots: [.top: rust.id, .bottom: grey.id, .footwear: all[9].id], score: 0, scoreParts: [:])
    let items = r.items().map(\.engineItem)
    let alts = OutfitEngine.alternatives(for: .bottom, in: base, intent: festival, items: items, context: EngineContext(today: .now, pairWeights: ws), limit: 10)
    let bi = try #require(alts.firstIndex { $0.slots[.bottom] == black.id })
    let ti = try #require(alts.firstIndex { $0.slots[.bottom] == twin.id })
    let pwBlack = try #require(alts[bi].scoreParts["pairWeight"]), pwTwin = try #require(alts[ti].scoreParts["pairWeight"])
    #expect(pwBlack > pwTwin)
    // Only the learned pair differs between the twins (variety is a seeded hash, so compare the parts that matter).
    #expect(alts[bi].scoreParts["occasionFit"] == alts[ti].scoreParts["occasionFit"])
    #expect(alts[bi].scoreParts["colourHarmony"] == alts[ti].scoreParts["colourHarmony"])
}

@MainActor @Test func S5_stylistEventsCarryItems() async throws {
    let r = try Rig(); defer { r.cleanup() }
    r.seed()
    let vm = r.vm()
    vm.choose(.festival)
    let shown = vm.outfits.map(\.candidate.itemIds)
    await vm.notesTask?.value
    vm.anotherOption()
    await vm.notesTask?.value
    let events = Learning.events(in: r.context)
    for ids in shown {
        let rej: LearningEvent = LearningEvent.rejected(ids)
        #expect(events.contains(rej))
    }

    let o = try #require(vm.outfits.first)
    vm.select(outfit: o.id, slot: .footwear)
    let alt = try #require(vm.swapOptions.first)
    let removed = try #require(o.candidate.slots[.footwear]), added = try #require(alt.slots[.footwear])
    vm.swap(to: alt)
    await vm.notesTask?.value
    let others = o.candidate.slots.filter { $0.key != .footwear }.map(\.value).sorted { $0.uuidString < $1.uuidString }
    let swap: LearningEvent = LearningEvent.swapped(removed: removed, added: added, others: others)
    #expect(Learning.events(in: r.context).contains(swap))
}

@MainActor @Test func S5_wornEventsComeFromWearLog() throws {
    let r = try Rig(); defer { r.cleanup() }
    let all = r.seed()
    WearLogger.markWorn(itemIds: [all[0].id, all[4].id], outfitId: nil, on: .now, in: r.context)
    let ws = Learning.pairWeights(in: r.context)
    #expect(abs(PairWeights.value(ws, all[0].id, all[4].id) - 0.65) < 1e-9)
}

// MARK: Sets (U17, U18, U19, I04)

@MainActor @Test func S5_U17_U18_linkAndUnlink() throws {
    let r = try Rig(); defer { r.cleanup() }
    let kurta = r.make("Kurta", .top, .kurta, .cream, dc: [.festive], origin: .indian)
    let pyjama = r.make("Pyjama", .bottom, .pyjama, .white, dc: [.festive], origin: .indian)
    let blouse = r.make("Blouse", .top, .blouse, .gold, dc: [.festive], origin: .indian)
    let saree = r.make("Saree", .onePiece, .saree, .maroon, dc: [.festive], origin: .indian)
    #expect(Item.linkSet([kurta, pyjama], in: r.context) == nil)
    #expect(Item.linkSet([blouse, saree], in: r.context) == nil)
    #expect(kurta.setGroupId != nil && kurta.setGroupId == pyjama.setGroupId)
    #expect(kurta.setRole == SetRole.kurta)
    #expect(pyjama.setRole == SetRole.kurtaBottom)
    #expect(kurta.engineItem.tags.setRole == .kurta && kurta.engineItem.setGroupId == kurta.setGroupId)
    Item.unlinkSet(kurta, in: r.context)
    #expect(kurta.setGroupId == nil)
    #expect(pyjama.setGroupId == nil)
    #expect(kurta.setRole == SetRole.none)
    #expect(pyjama.setRole == SetRole.none)
    #expect(blouse.setGroupId != nil && blouse.setGroupId == saree.setGroupId)
}

@MainActor @Test func S5_U19_invalidLinkRefused() throws {
    let r = try Rig(); defer { r.cleanup() }
    let a = r.make("Kurta", .top, .kurta, .cream), b = r.make("Shirt", .top, .shirt, .white)
    let reason = Item.linkSet([a, b], in: r.context)
    #expect(reason?.isEmpty == false && a.setGroupId == nil && b.setGroupId == nil)
    #expect(Item.linkSet([a], in: r.context) != nil)
}

@MainActor @Test func S5_I04_linkedSetSuggestedTogether() throws {
    let r = try Rig(); defer { r.cleanup() }
    r.seed()
    let kurta = r.make("Kurta", .top, .kurta, .cream, dc: [.festive, .smartCasual], origin: .indian)
    let pyjama = r.make("Pyjama", .bottom, .pyjama, .white, dc: [.festive, .smartCasual], origin: .indian)
    #expect(Item.linkSet([kurta, pyjama], in: r.context) == nil)
    var intent = festival; intent.preferIndian = true
    let res = OutfitEngine.generate(intent: intent, items: r.items().map(\.engineItem), count: 5)
    #expect(res.outfits.contains { $0.itemIds.contains(kurta.id) })
    for o in res.outfits { #expect(o.itemIds.contains(kurta.id) == o.itemIds.contains(pyjama.id)) }
}

// MARK: Export / import (U20, U21, U22)

@MainActor @Test func S5_U20_exportContent() throws {
    let r = try Rig(); defer { r.cleanup() }
    let all = r.seed()
    all[0].setOverride(\.fabric, to: .linen, context: r.context)
    let k = r.make("Kurta", .top, .kurta, .cream), p = r.make("Pyjama", .bottom, .pyjama, .white)
    _ = Item.linkSet([k, p], in: r.context)
    OutfitSaver.save(id: UUID(), slots: [.top: all[0].id, .bottom: all[4].id], occasion: .office, note: "n", in: r.context)
    WearLogger.markWorn(itemIds: [all[0].id], outfitId: nil, on: .now, in: r.context)
    let data = try WardrobeExport.data(from: r.context)
    let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    let items = try #require(json["items"] as? [[String: Any]])
    #expect(items.count == all.count + 2)
    let first = try #require(items.first { $0["id"] as? String == all[0].id.uuidString })
    for key in ["tags", "aiRaw", "userOverrides", "colorNames", "hexColors", "name"] { #expect(first[key] != nil, "\(key)") }
    #expect((first["tags"] as? [String: Any])?["fabric"] as? String == "linen")
    #expect((first["aiRaw"] as? [String: Any])?["fabric"] == nil)
    let kurta = try #require(items.first { $0["id"] as? String == k.id.uuidString })
    #expect(kurta["setGroupId"] as? String == k.setGroupId?.uuidString && kurta["setRole"] as? String == "kurta")
    #expect((json["outfits"] as? [Any])?.count == 1 && (json["wearLog"] as? [Any])?.count == 1)
    let text = String(decoding: data, as: UTF8.self)
    #expect(!text.contains(".jpg") && !text.contains(".png"))
}

@MainActor @Test func S5_U21_U22_roundTripWithoutImages() throws {
    let r = try Rig(); defer { r.cleanup() }
    let all = r.seed()
    all[2].setOverride(\.fabric, to: .linen, context: r.context)
    let k = r.make("Kurta", .top, .kurta, .cream), p = r.make("Pyjama", .bottom, .pyjama, .white)
    _ = Item.linkSet([k, p], in: r.context)
    OutfitSaver.save(id: UUID(), slots: [.top: all[0].id, .bottom: all[4].id, .footwear: all[9].id], occasion: .office, note: nil, in: r.context)
    let data = try WardrobeExport.data(from: r.context)

    let fresh = try Rig(); defer { fresh.cleanup() }
    let n = try WardrobeExport.importData(data, into: fresh.context)
    let got = fresh.items()
    #expect(n == all.count + 2 && got.count == all.count + 2)
    for i in r.items() {
        let j = try #require(got.first { $0.id == i.id })
        #expect(j.tags == i.tags)
        #expect(j.aiRaw == i.aiRaw)
        #expect(j.userOverrides == i.userOverrides)
        #expect(j.name == i.name)
        #expect(j.setGroupId == i.setGroupId)
        #expect(j.setRole == i.setRole)
        #expect(j.colorNames == i.colorNames)
        #expect(j.status == .ready && !j.hasImage)
    }
    #expect(count(fresh.context, Outfit.self) == 1 && count(fresh.context, OutfitItem.self) == 3)
    // Usable by the engine without images.
    let res = OutfitEngine.generate(intent: festival, items: got.map(\.engineItem))
    #expect(!res.outfits.isEmpty)
}

// MARK: Settings and delete (U23, U24, I05)

@MainActor @Test func S5_U23_settingsCounts() throws {
    let r = try Rig(); defer { r.cleanup() }
    let all = r.seed()
    OutfitSaver.save(id: UUID(), slots: [.top: all[0].id, .bottom: all[4].id], occasion: nil, note: nil, in: r.context)
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    for (purpose, secs, ago) in [("tagA", 2.0, 1.0), ("tagB", 4.0, 2.0), ("tagC", 9.0, 3.0), ("note", 1.0, 1.0), ("tagA", 3.0, 10.0)] {
        r.context.insert(AIRequestLog(purpose: purpose, provider: "p", model: "m", durationSeconds: secs, success: true, createdAt: now.addingTimeInterval(-ago * day)))
    }
    try r.context.save()
    let s = SettingsStats.compute(in: r.context, now: now)
    #expect(s.items == all.count && s.outfits == 1 && s.aiCallsThisWeek == 4)
    #expect(s.medianTaggingSeconds == 4.0)
}

@MainActor @Test func S5_U24_I05_deleteAllLeavesNothing() async throws {
    let r = try Rig(); defer { r.cleanup() }
    let all = r.seed()
    for i in all { try r.store.save(Data([1, 2, 3]), named: "display.jpg", for: i.id) }
    OutfitSaver.save(id: UUID(), slots: [.top: all[0].id, .bottom: all[4].id], occasion: nil, note: nil, in: r.context)
    WearLogger.markWorn(itemIds: [all[0].id], outfitId: nil, on: .now, in: r.context)
    let vm = r.vm(); vm.choose(.festival); await vm.notesTask?.value
    DataReset.deleteAll(in: r.context, store: r.store)
    #expect(DataReset.counts(in: r.context) == .init())
    #expect(count(r.context, OutfitItem.self) == 0)
    let left = (try? FileManager.default.contentsOfDirectory(atPath: r.store.root.path)) ?? []
    #expect(left.isEmpty)
}
