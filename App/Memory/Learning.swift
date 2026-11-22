import Foundation
import StyleEngine
import SwiftData

/// Sprint 5: turns the stored history into the engine's pair weights. Recomputed every time, never stored.
enum Learning {
    static func events(in c: ModelContext) -> [LearningEvent] {
        func sorted(_ ids: [UUID]) -> [UUID] { ids.sorted { $0.uuidString < $1.uuidString } }
        var out: [LearningEvent] = []
        let feedback = ((try? c.fetch(FetchDescriptor<FeedbackEvent>(sortBy: [SortDescriptor(\.createdAt)]))) ?? [])
        for e in feedback {
            switch e.action {
            case "saved" where e.itemIds.count >= 2: out.append(.saved(sorted(e.itemIds)))
            case "rejected" where e.itemIds.count >= 2: out.append(.rejected(sorted(e.itemIds)))
            case "swapped":
                if let r = e.removedItemId, let a = e.addedItemId { out.append(.swapped(removed: r, added: a, others: sorted(e.itemIds))) }
            default: break
            }
        }
        for w in (try? c.fetch(FetchDescriptor<WearLog>())) ?? [] where w.itemIds.count >= 2 { out.append(.worn(sorted(w.itemIds))) }
        return out
    }

    static func pairWeights(in c: ModelContext) -> [PairKey: Double] { PairWeights.compute(events(in: c)) }
}

/// Mark worn: one `WearLog` row and `lastWornAt` on each item (never moved back by a backdated entry).
enum WearLogger {
    static func markWorn(itemIds: [UUID], outfitId: UUID?, on date: Date, in c: ModelContext) {
        c.insert(WearLog(outfitId: outfitId, itemIds: itemIds, date: date))
        let ids = Set(itemIds)
        for item in (try? c.fetch(FetchDescriptor<Item>())) ?? [] where ids.contains(item.id) {
            if item.lastWornAt.map({ $0 < date }) ?? true { item.lastWornAt = date }
        }
        try? c.save()
    }
}

extension Item {
    /// Times this item is in the wear log.
    func wearCount(in c: ModelContext) -> Int {
        ((try? c.fetch(FetchDescriptor<WearLog>())) ?? []).filter { $0.itemIds.contains(id) }.count
    }

    /// Items worn together in the log, newest first.
    func wearDates(in c: ModelContext) -> [Date] {
        ((try? c.fetch(FetchDescriptor<WearLog>())) ?? []).filter { $0.itemIds.contains(id) }.map(\.date).sorted(by: >)
    }

    /// Links items as one set: a shared group id and a role each. Returns why not, or nil on success.
    @discardableResult
    static func linkSet(_ items: [Item], in c: ModelContext) -> String? {
        switch SetLink.roles(for: items.map(\.engineItem)) {
        case .failure(let e): return e.reason
        case .success(let roles):
            let group = UUID()
            for i in items { i.setGroupId = group; i.setRole = roles[i.id] ?? .none }
            try? c.save()
            return nil
        }
    }

    /// Unlinks every member of this item's set.
    static func unlinkSet(_ item: Item, in c: ModelContext) {
        guard let g = item.setGroupId else { return }
        for i in (try? c.fetch(FetchDescriptor<Item>())) ?? [] where i.setGroupId == g { i.setGroupId = nil; i.setRole = .none }
        try? c.save()
    }

    var hasImage: Bool { !originalFile.isEmpty }
}
