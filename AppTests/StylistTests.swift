import Foundation
import StyleEngine
import SwiftData
import Testing
import WardrobeImaging
@testable import AIStylist

// Sprint 4 app-side tests (SPRINT_4_TESTS.md). Fakes only: the real model is never called here.

@MainActor private func memoryContainer() throws -> ModelContainer {
    try ModelContainer(for: Schema(Item.allModels), configurations: ModelConfiguration(isStoredInMemoryOnly: true))
}
private func tempDir() -> URL {
    let d = FileManager.default.temporaryDirectory.appendingPathComponent("aistylist-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
    return d
}

/// 4 tops, 4 bottoms and 3 shoes that all pass a smart-casual festival evening; some items have a pattern or colour of their own.
@MainActor @discardableResult private func seed(_ c: ModelContext) -> [Item] {
    func make(_ name: String, _ cat: StyleEngine.Category, _ sub: Subcategory, _ colour: ColorName) -> Item {
        let i = Item(originalFile: "original.jpg", cutoutFile: "cutout.png", displayFile: "display.jpg")
        var t = ItemTags(); t.category = cat; t.subcategory = sub; t.styleOrigin = .western; t.pattern = .solid
        t.dressCodes = [.smartCasual]; t.formality = 3; t.seasons = [.summer, .monsoon, .winter]; t.warmth = 1; t.statement = .plain
        if cat == .footwear { t.closedToe = true }
        i.aiRawData = try? JSONEncoder().encode(t); i.name = name; i.colorNames = [colour.rawValue]; i.status = .ready
        c.insert(i); return i
    }
    let items = [
        make("Rust shirt", .top, .shirt, .rust), make("Cream shirt", .top, .shirt, .cream),
        make("Olive polo", .top, .polo, .olive), make("White tee", .top, .tshirt, .white),
        make("Black chinos", .bottom, .chinos, .black), make("Navy trousers", .bottom, .trousers, .navy),
        make("Beige chinos", .bottom, .chinos, .beige), make("Grey trousers", .bottom, .trousers, .grey),
        make("White sneakers", .footwear, .sneakers, .white), make("Black loafers", .footwear, .loafers, .black),
        make("Brown loafers", .footwear, .loafers, .brown),
    ]
    try? c.save()
    return items
}

private let festival = OccasionIntent(occasion: .festival, timeOfDay: .evening, setting: .indoor)
private func count<T: PersistentModel>(_ c: ModelContext, _ t: T.Type) -> Int { (try? c.fetchCount(FetchDescriptor<T>())) ?? -1 }
private func logs(_ c: ModelContext, _ purpose: String) -> [AIRequestLog] {
    ((try? c.fetch(FetchDescriptor<AIRequestLog>())) ?? []).filter { $0.purpose == purpose }
}

@MainActor private struct Rig {
    let container: ModelContainer, parser: FakeIntentParser, writer: FakeNoteWriter, vm: StylistViewModel
    var context: ModelContext { container.mainContext }
    /// Wait for the notes task: it writes a log row, so it must finish before the container goes away.
    func settle() async { await vm.notesTask?.value }
    init(parser: FakeIntentParser = FakeIntentParser(), writer: FakeNoteWriter = FakeNoteWriter()) throws {
        container = try memoryContainer(); self.parser = parser; self.writer = writer
        seed(container.mainContext)
        vm = StylistViewModel(parser: parser, writer: writer, context: container.mainContext, store: ImageStore(root: tempDir()))
    }
}

// MARK: Save, notes, cascade, feedback (U21-U24)

@MainActor @Test func S4_U21_saveCreatesRows() async throws {
    let r = try Rig(); r.vm.choose(.festival)
    let o = try #require(r.vm.outfits.first)
    #expect(r.vm.save(o.id))
    let saved = try #require(try r.context.fetch(FetchDescriptor<Outfit>()).first)
    #expect(saved.source == .ai && saved.occasion == Occasion.festival.rawValue && saved.saved && saved.id == o.id)
    let rows = try r.context.fetch(FetchDescriptor<OutfitItem>())
    #expect(rows.count == o.candidate.slots.count && Set(rows.map(\.slot)) == Set(o.candidate.slots.keys.map(\.rawValue)))
    #expect(Set(rows.map(\.itemId)) == Set(o.candidate.slots.values))
    #expect(!r.vm.save(o.id) && count(r.context, Outfit.self) == 1)   // saving twice is a no-op
    await r.settle()
}

@MainActor @Test func S4_U22_noteStoredOrNone() async throws {
    let r = try Rig(); await r.vm.send("diwali")
    await r.vm.notesTask?.value
    let (a, b) = (r.vm.outfits[0], r.vm.outfits[1])
    #expect(r.vm.notes[a.id] != nil)
    r.vm.save(a.id)
    #expect(try r.context.fetch(FetchDescriptor<Outfit>()).first { $0.id == a.id }?.note == r.vm.notes[a.id])
    // Same flow, but the writer's note names an absent item: that outfit saves with none.
    let w = FakeNoteWriter(.success(["The jacket adds polish.", "x", "y"]))
    let r2 = try Rig(writer: w); await r2.vm.send("diwali"); await r2.vm.notesTask?.value
    let first = r2.vm.outfits[0]
    r2.vm.save(first.id)
    #expect(try r2.context.fetch(FetchDescriptor<Outfit>()).first { $0.id == first.id }?.note == nil)
    _ = b
}

@MainActor @Test func S4_U23_deletingAnItemCascades() throws {
    let c = try memoryContainer(), store = ImageStore(root: tempDir())
    let items = seed(c.mainContext)
    func save(_ ids: [Item]) -> UUID {
        let slots: [Slot: UUID] = [.top: ids[0].id, .bottom: ids[1].id, .footwear: ids[2].id]
        return OutfitSaver.save(id: UUID(), slots: slots, occasion: .festival, note: nil, in: c.mainContext).id
    }
    let keep = save([items[0], items[4], items[8]])      // shares the top and bottom with the other outfit
    let other = save([items[1], items[5], items[8]])
    Item.delete(items[8], in: c.mainContext, store: store)       // shoes in both: each keeps 2 items
    #expect(count(c.mainContext, Outfit.self) == 2 && count(c.mainContext, OutfitItem.self) == 4)
    Item.delete(items[0], in: c.mainContext, store: store)       // `keep` is down to 1 item: deleted with its rows
    let left = try c.mainContext.fetch(FetchDescriptor<Outfit>())
    #expect(left.map(\.id) == [other] && !left.contains { $0.id == keep })
    let rows = try c.mainContext.fetch(FetchDescriptor<OutfitItem>())
    #expect(rows.count == 2 && rows.allSatisfy { $0.outfitId == other })
    #expect(!rows.contains { $0.itemId == items[0].id || $0.itemId == items[8].id })
}

@MainActor @Test func S4_U24_feedbackEvents() async throws {
    let r = try Rig(); r.vm.choose(.festival)
    let first = r.vm.outfits.map(\.id)
    func events(_ action: String) -> [FeedbackEvent] { ((try? r.context.fetch(FetchDescriptor<FeedbackEvent>())) ?? []).filter { $0.action == action } }
    r.vm.anotherOption()
    #expect(Set(events("rejected").map(\.outfitId)) == Set(first) && events("rejected").count == 3)
    let o = r.vm.outfits[0]
    r.vm.select(outfit: o.id, slot: .footwear)
    let alt = try #require(r.vm.swapOptions.first)
    r.vm.swap(to: alt)
    #expect(events("swapped").count == 1 && events("swapped")[0].slot == Slot.footwear.rawValue && events("swapped")[0].outfitId == o.id)
    r.vm.save(o.id)
    #expect(events("saved").count == 1 && events("saved")[0].outfitId == o.id)
    await r.settle()
}

// MARK: Chips, session through the view model (U06, U08)

@MainActor @Test func S4_U06_chipsNeverCallTheParser() async throws {
    let r = try Rig(); r.vm.choose(.festival)
    #expect(r.parser.calls == 0 && r.vm.intent == IntentMerge.chipIntent(for: .festival) && r.vm.outfits.count == 3)
    #expect(logs(r.context, "intent").isEmpty)
    await r.settle()
}

@MainActor @Test func S4_U08_editingAChipClearsShownAndSkipsTheParser() async throws {
    let r = try Rig(); r.vm.choose(.festival); r.vm.anotherOption()
    #expect(r.vm.session.shown.count == 6)
    r.vm.edit { $0.timeOfDay = .night }
    #expect(r.vm.intent?.timeOfDay == .night && r.vm.session.shown.count == r.vm.outfits.count && r.vm.outfits.count == 3)
    #expect(r.parser.calls == 0 && logs(r.context, "intent").isEmpty)
    await r.settle()
}

// MARK: Integration (I01-I09)

@MainActor @Test func S4_I01_messageToCards() async throws {
    let r = try Rig(); await r.vm.send("Diwali at a friend's place")
    #expect(r.vm.outfits.count == 3 && r.parser.calls == 1 && r.parser.messages == ["Diwali at a friend's place"])
    await r.settle()
}

@MainActor @Test func S4_I02_mergedIntentReachesTheEngine() async throws {
    let r = try Rig(); await r.vm.send("diwali")
    #expect(r.vm.intent == festival)
    // What the chips show is `vm.intent`; the engine run with it gives the same three outfits.
    let engine = OutfitEngine.generate(intent: festival, items: try r.context.fetch(FetchDescriptor<Item>()).map(\.engineItem),
                                       context: EngineContext(today: r.vm.today))
    #expect(r.vm.outfits.map(\.candidate.key) == engine.outfits.map(\.key))
    // A follow-up passes the previous intent and recent messages to the parser.
    await r.vm.send("make it casual")
    #expect(r.parser.previous.last! == festival && r.parser.recent.last! == ["diwali"])
    await r.settle()
}

@MainActor @Test func S4_I03_parserFailureFallsBackToCasualDay() async throws {
    let r = try Rig(parser: FakeIntentParser(.failure(FakeIntentParser.Boom()))); await r.vm.send("anything")
    #expect(r.vm.intent == IntentMerge.chipIntent(for: .casualDay))
    #expect(!r.vm.outfits.isEmpty)
    #expect(logs(r.context, "intent").count == 1 && logs(r.context, "intent")[0].success == false)
    await r.settle()
}

@MainActor @Test func S4_I04_anotherOptionNeverRepeats() async throws {
    let r = try Rig(); r.vm.choose(.festival)
    var seen = r.vm.outfits.map(\.candidate.key)
    for _ in 0..<3 {
        r.vm.anotherOption()
        let keys = r.vm.outfits.map(\.candidate.key)
        #expect(keys.count == 3 && Set(keys).isDisjoint(with: Set(seen)))
        seen += keys
    }
    #expect(Set(seen).count == 12)
    await r.settle()
}

@MainActor @Test func S4_I05_cardsBeforeNotes() async throws {
    let w = FakeNoteWriter(); w.delay = .seconds(5)
    let r = try Rig(writer: w); await r.vm.send("diwali")
    #expect(r.vm.outfits.count == 3 && r.vm.notes.isEmpty)       // cards are there, notes are still being written
    r.vm.notesTask?.cancel(); await r.settle()
    let quick = FakeNoteWriter(); quick.delay = .milliseconds(50)
    let r2 = try Rig(writer: quick); await r2.vm.send("diwali")
    #expect(r2.vm.notes.isEmpty)
    await r2.vm.notesTask?.value
    #expect(r2.vm.notes.count == 3)
}

@MainActor @Test func S4_I06_noteWriterFailureIsSilent() async throws {
    let r = try Rig(writer: FakeNoteWriter(.failure(FakeNoteWriter.Boom()))); await r.vm.send("diwali")
    await r.vm.notesTask?.value
    #expect(r.vm.outfits.count == 3 && r.vm.notes.isEmpty && r.vm.errorMessage == nil)
    #expect(logs(r.context, "note").count == 1 && logs(r.context, "note")[0].success == false)
}

@MainActor @Test func S4_I07_hallucinatedNoteDropsOnlyThatCard() async throws {
    let r = try Rig(writer: FakeNoteWriter(.success(["Great, the jacket adds polish.", "A relaxed evening look.", "Easy and comfortable."])))
    await r.vm.send("diwali"); await r.vm.notesTask?.value
    let ids = r.vm.outfits.map(\.id)
    #expect(r.vm.notes[ids[0]] == nil && r.vm.notes[ids[1]] != nil && r.vm.notes[ids[2]] != nil)
}

@MainActor @Test func S4_I08_logRows() async throws {
    let r = try Rig(); await r.vm.send("diwali"); await r.vm.notesTask?.value
    #expect(logs(r.context, "intent").count == 1 && logs(r.context, "note").count == 1)
    #expect(logs(r.context, "intent")[0].provider == "onDevice" && logs(r.context, "intent")[0].success)
    r.vm.choose(.office); r.vm.edit { $0.setting = .outdoor }          // chip taps: no AI call, no row
    #expect(logs(r.context, "intent").count == 1)
    await r.vm.send("again")
    #expect(logs(r.context, "intent").count == 2)
    await r.settle()
}

@MainActor @Test func S4_I09_saveAndReload() async throws {
    let dir = tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
    let url = dir.appendingPathComponent("test.store")
    let id: UUID, slots: [Slot: UUID], note: String?
    do {
        let c = try ModelContainer(for: Schema(Item.allModels), configurations: ModelConfiguration(url: url))
        seed(c.mainContext)
        let vm = StylistViewModel(parser: FakeIntentParser(), writer: FakeNoteWriter(), context: c.mainContext, store: ImageStore(root: dir))
        await vm.send("diwali"); await vm.notesTask?.value
        let o = vm.outfits[0]; vm.save(o.id)
        id = o.id; slots = o.candidate.slots; note = vm.notes[o.id]
    }
    let again = try ModelContainer(for: Schema(Item.allModels), configurations: ModelConfiguration(url: url))
    let outfit = try #require(try again.mainContext.fetch(FetchDescriptor<Outfit>()).first)
    let rows = try again.mainContext.fetch(FetchDescriptor<OutfitItem>())
    #expect(outfit.id == id && outfit.occasion == "festival" && outfit.note == note && note != nil)
    #expect(Dictionary(uniqueKeysWithValues: rows.map { (Slot(rawValue: $0.slot)!, $0.itemId) }) == slots)
}

// MARK: UI smoke (no UI test target: the same steps, in process)

@MainActor @Test func S4_UI01_festivalChipSaveThenOutfitsTab() async throws {
    let r = try Rig()
    r.vm.choose(.festival)                                           // Stylist tab, Festival chip
    #expect(r.vm.outfits.count == 3)                                 // three cards
    #expect(r.vm.save(r.vm.outfits[0].id))                           // Save on the first card
    let tab = OutfitsView.saved(in: r.context)                       // the Outfits tab's list
    #expect(tab.count == 1 && OutfitsView.filter(tab, occasion: .festival).count == 1 && OutfitsView.filter(tab, occasion: .office).isEmpty)
    _ = ContentView()                                                // the tab view builds
    await r.settle()
}

// MARK: Fix round 1 (device test 15 Nov)

@MainActor @Test func S4_F08_saverRefusesADuplicateItemSet() throws {
    let c = try memoryContainer(); let items = seed(c.mainContext)
    let slots: [Slot: UUID] = [.top: items[0].id, .bottom: items[4].id, .footwear: items[8].id]
    let a = OutfitSaver.save(id: UUID(), slots: slots, occasion: .festival, note: nil, in: c.mainContext)
    let b = OutfitSaver.save(id: UUID(), slots: slots, occasion: .office, note: "x", in: c.mainContext)   // same set, other id
    #expect(a.id == b.id && count(c.mainContext, Outfit.self) == 1 && count(c.mainContext, OutfitItem.self) == 3)
    #expect(count(c.mainContext, FeedbackEvent.self) == 1)
}

@MainActor @Test func S4_F09_savedShowsSavedWhenReshownAndSwapIsANewOutfit() async throws {
    let r = try Rig(); r.vm.choose(.festival)
    let o = r.vm.outfits[0]
    #expect(r.vm.save(o.id) && r.vm.isSaved(o.id))
    // Same item set shown under another id (engine shows it again later): saved, and save refuses.
    r.vm.choose(.festival)
    let again = try #require(r.vm.outfits.first { $0.candidate.key == o.candidate.key })
    #expect(again.id != o.id && r.vm.isSaved(again.id) && !r.vm.save(again.id) && count(r.context, Outfit.self) == 1)
    // After a swap the item set differs: not saved, can be saved, and the first save stays.
    r.vm.select(outfit: again.id, slot: .footwear)
    r.vm.swap(to: try #require(r.vm.swapOptions.first))
    #expect(!r.vm.isSaved(again.id) && r.vm.save(again.id) && count(r.context, Outfit.self) == 2)
    await r.settle()
}

@MainActor @Test func S4_F10_noFootwearStillShowsOutfitsWithAHint() async throws {
    let r = try Rig()
    for i in try r.context.fetch(FetchDescriptor<Item>()) where i.tags.category == .footwear { r.context.delete(i) }
    try r.context.save()
    r.vm.choose(.festival)
    #expect(!r.vm.outfits.isEmpty && r.vm.softMissing == [.footwear] && r.vm.outfits.allSatisfy { $0.candidate.slots[.footwear] == nil })
    await r.settle()
}
