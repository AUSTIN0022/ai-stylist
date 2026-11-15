import Foundation
import StyleEngine
import SwiftData

enum OutfitSaver {
    /// The saved outfit with exactly this set of items, if any.
    static func existing(slots: [Slot: UUID], in context: ModelContext) -> Outfit? {
        let want = Set(slots.values)
        let rows = (try? context.fetch(FetchDescriptor<OutfitItem>())) ?? []
        let byOutfit = Dictionary(grouping: rows, by: \.outfitId).mapValues { Set($0.map(\.itemId)) }
        return ((try? context.fetch(FetchDescriptor<Outfit>())) ?? []).first { $0.saved && byOutfit[$0.id] == want }
    }

    /// A saved AI outfit: one `Outfit`, one `OutfitItem` per slot, one `saved` event. `id` is the shown outfit's id, so events line up
    /// (a fresh id when that one is taken by an earlier version of the outfit). The same item set is never saved twice: the saved one is returned.
    @discardableResult
    static func save(id: UUID, slots: [Slot: UUID], occasion: Occasion?, note: String?, in context: ModelContext) -> Outfit {
        if let e = existing(slots: slots, in: context) { return e }
        let taken = ((try? context.fetchCount(FetchDescriptor<Outfit>(predicate: #Predicate { $0.id == id }))) ?? 0) > 0
        let id = taken ? UUID() : id
        let o = Outfit(id: id, name: "\(occasion?.title ?? "My") outfit", source: .ai)
        o.occasion = occasion?.rawValue; o.note = note; o.saved = true
        context.insert(o)
        for (slot, item) in slots { context.insert(OutfitItem(outfitId: id, itemId: item, slot: slot.rawValue)) }
        context.insert(FeedbackEvent(outfitId: id, action: "saved"))
        try? context.save()
        return o
    }
}

extension OutfitSaver {
    /// Slot to item id for a saved outfit.
    static func slots(of outfit: Outfit, rows: [OutfitItem]) -> [Slot: UUID] {
        Dictionary(rows.filter { $0.outfitId == outfit.id }.compactMap { r in Slot(rawValue: r.slot).map { ($0, r.itemId) } }, uniquingKeysWith: { a, _ in a })
    }

    /// Deletes the outfit and its item rows. The wardrobe items stay.
    static func delete(_ outfit: Outfit, in context: ModelContext) {
        let id = outfit.id
        for r in (try? context.fetch(FetchDescriptor<OutfitItem>(predicate: #Predicate { $0.outfitId == id }))) ?? [] { context.delete(r) }
        context.delete(outfit)
        try? context.save()
    }
}
