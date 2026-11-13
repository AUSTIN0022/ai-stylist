import Foundation
import SwiftData
import WardrobeImaging

/// Delete all data: every row of every model and the whole image folder.
enum DataReset {
    struct Counts: Equatable {
        var items = 0, outfits = 0, wearLogs = 0, aiLogs = 0, feedback = 0
        /// "12 items, 3 outfits, 40 AI log rows" (zero counts left out).
        var summary: String {
            func n(_ k: Int, _ one: String, _ many: String) -> String? { k == 0 ? nil : "\(k) \(k == 1 ? one : many)" }
            let parts = [n(items, "item", "items"), n(outfits, "outfit", "outfits"), n(wearLogs, "wear log", "wear logs"),
                         n(feedback, "feedback event", "feedback events"), n(aiLogs, "AI log row", "AI log rows")].compactMap { $0 }
            return parts.isEmpty ? "nothing" : parts.joined(separator: ", ")
        }
    }

    static func counts(in c: ModelContext) -> Counts {
        Counts(items: (try? c.fetchCount(FetchDescriptor<Item>())) ?? 0, outfits: (try? c.fetchCount(FetchDescriptor<Outfit>())) ?? 0,
               wearLogs: (try? c.fetchCount(FetchDescriptor<WearLog>())) ?? 0, aiLogs: (try? c.fetchCount(FetchDescriptor<AIRequestLog>())) ?? 0,
               feedback: (try? c.fetchCount(FetchDescriptor<FeedbackEvent>())) ?? 0)
    }

    @MainActor static func deleteAll(in c: ModelContext, store: ImageStore) {
        for item in (try? c.fetch(FetchDescriptor<Item>())) ?? [] { Item.delete(item, in: c, store: store) }   // the existing per-item delete
        try? c.delete(model: OutfitItem.self); try? c.delete(model: Outfit.self); try? c.delete(model: WearLog.self)
        try? c.delete(model: FeedbackEvent.self); try? c.delete(model: AIRequestLog.self)
        try? c.save()
        // Anything left in the image folder (orphans, temporary review folders).
        try? FileManager.default.removeItem(at: store.root)
    }
}
