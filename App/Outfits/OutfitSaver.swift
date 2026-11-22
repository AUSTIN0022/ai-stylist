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
        context.insert(FeedbackEvent(outfitId: id, action: "saved", itemIds: Array(slots.values)))
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

// MARK: Sprint 5: outfits built or edited in the builder

extension OutfitSaver {
    /// An outfit needs two things on the canvas (the same floor the item-delete cascade uses).
    static func canSave(_ canvas: OutfitCanvas) -> Bool { canvas.items.count >= 2 }

    /// The builder's starting layout: the stored one (items still in the outfit only), else the card layout.
    static func canvas(for outfit: Outfit, rows: [OutfitItem]) -> OutfitCanvas {
        let slots = slots(of: outfit, rows: rows)
        let ids = Set(slots.values)
        if let c = outfit.canvas, Set(c.items.map(\.itemId)) == ids { return c }
        return OutfitCanvas(slots: slots)
    }

    /// Saves the builder's canvas. New outfits are `manual`; an edited one keeps its id and source. Slots are inferred
    /// from category. A new outfit, or a changed item set, writes a `saved` event (a hand-made pairing is a strong signal).
    @discardableResult
    static func saveManual(_ canvas: OutfitCanvas, name: String?, occasion: Occasion?, editing: Outfit?, in context: ModelContext) -> Outfit {
        let ids = canvas.items.map(\.itemId)
        let all = (try? context.fetch(FetchDescriptor<Item>())) ?? []
        let byId = Dictionary(all.map { ($0.id, $0.engineItem) }, uniquingKeysWith: { a, _ in a })
        let slotOf = OutfitSlots.infer(ids.compactMap { byId[$0] })
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        let o: Outfit
        var changed = true
        if let editing {
            o = editing
            let oid = o.id
            let old = (try? context.fetch(FetchDescriptor<OutfitItem>(predicate: #Predicate { $0.outfitId == oid }))) ?? []
            changed = Set(old.map(\.itemId)) != Set(slotOf.keys)
            old.forEach(context.delete)
        } else {
            o = Outfit(name: "\(occasion?.title ?? "My") outfit", source: .manual)
            o.saved = true
            context.insert(o)
        }
        if let trimmed, !trimmed.isEmpty { o.name = trimmed }
        if let occasion { o.occasion = occasion.rawValue }
        o.canvasLayoutData = try? JSONEncoder().encode(canvas)
        for (id, slot) in slotOf { context.insert(OutfitItem(outfitId: o.id, itemId: id, slot: slot.rawValue)) }
        if changed { context.insert(FeedbackEvent(outfitId: o.id, action: "saved", itemIds: Array(slotOf.keys))) }
        try? context.save()
        return o
    }
}
