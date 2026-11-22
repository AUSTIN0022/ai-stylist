import Foundation
import StyleEngine
import SwiftData

/// Sprint 5: the wardrobe as one JSON file (items with merged and raw tags, outfits, wear log). No image data.
/// Import creates items without images; it is how the wardrobe.json fixture gets into a test build.
enum WardrobeExport {
    struct File: Codable {
        var version = 1
        var items: [ItemRow], outfits: [OutfitRow], wearLog: [WearRow]
    }
    struct ItemRow: Codable {
        var id: UUID, name: String, caption: String, status: String
        var tags: ItemTags, aiRaw: ItemTags, userOverrides: ItemTags
        var colorNames: [String], hexColors: [String]
        var setGroupId: UUID?, setRole: String
        var lastWornAt: Date?
    }
    struct OutfitRow: Codable {
        var id: UUID, name: String, source: String, occasion: String?, note: String?, createdAt: Date
        var slots: [String: UUID]
        var canvas: OutfitCanvas?
    }
    struct WearRow: Codable {
        var outfitId: UUID?
        var itemIds: [UUID]
        var date: Date
    }

    static func data(from c: ModelContext) throws -> Data {
        let items = ((try? c.fetch(FetchDescriptor<Item>(sortBy: [SortDescriptor(\.createdAt)]))) ?? []).map { i in
            ItemRow(id: i.id, name: i.name, caption: i.caption, status: i.status.rawValue, tags: i.tags, aiRaw: i.aiRaw,
                    userOverrides: i.userOverrides, colorNames: i.colorNames, hexColors: i.hexColors,
                    setGroupId: i.setGroupId, setRole: i.setRole.rawValue, lastWornAt: i.lastWornAt)
        }
        let rows = (try? c.fetch(FetchDescriptor<OutfitItem>())) ?? []
        let outfits = ((try? c.fetch(FetchDescriptor<Outfit>())) ?? []).map { o in
            OutfitRow(id: o.id, name: o.name, source: o.source.rawValue, occasion: o.occasion, note: o.note, createdAt: o.createdAt,
                      slots: Dictionary(rows.filter { $0.outfitId == o.id }.map { ($0.slot, $0.itemId) }, uniquingKeysWith: { a, _ in a }),
                      canvas: o.canvas)
        }
        let wear = ((try? c.fetch(FetchDescriptor<WearLog>())) ?? []).map { WearRow(outfitId: $0.outfitId, itemIds: $0.itemIds, date: $0.date) }
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]; e.dateEncodingStrategy = .iso8601
        return try e.encode(File(items: items, outfits: outfits, wearLog: wear))
    }

    /// Writes the export to a temporary file for the share sheet.
    static func file(from c: ModelContext) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("wardrobe-export.json")
        try data(from: c).write(to: url, options: .atomic)
        return url
    }

    /// Adds the file's items, outfits and wear log; rows whose id already exists are skipped. Returns the number of items added.
    @discardableResult
    static func importData(_ d: Data, into c: ModelContext) throws -> Int {
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        let f = try dec.decode(File.self, from: d)
        let haveItems = Set(((try? c.fetch(FetchDescriptor<Item>())) ?? []).map(\.id))
        let haveOutfits = Set(((try? c.fetch(FetchDescriptor<Outfit>())) ?? []).map(\.id))
        var added = 0
        for r in f.items where !haveItems.contains(r.id) {
            let i = Item(id: r.id, originalFile: "", cutoutFile: nil, displayFile: "")
            i.status = ItemStatus(rawValue: r.status) ?? .ready
            if i.status == .tagging { i.status = .ready }
            i.name = r.name; i.caption = r.caption; i.colorNames = r.colorNames; i.hexColors = r.hexColors
            i.aiRawData = try JSONEncoder().encode(r.aiRaw)
            i.userOverridesData = r.userOverrides == ItemTags() ? nil : try JSONEncoder().encode(r.userOverrides)
            i.setGroupId = r.setGroupId; i.setRole = SetRole(rawValue: r.setRole) ?? .none; i.lastWornAt = r.lastWornAt
            c.insert(i); added += 1
        }
        for r in f.outfits where !haveOutfits.contains(r.id) {
            let o = Outfit(id: r.id, name: r.name, source: OutfitSource(rawValue: r.source) ?? .ai)
            o.occasion = r.occasion; o.note = r.note; o.createdAt = r.createdAt; o.saved = true
            o.canvasLayoutData = try r.canvas.map { try JSONEncoder().encode($0) }
            c.insert(o)
            for (slot, id) in r.slots { c.insert(OutfitItem(outfitId: r.id, itemId: id, slot: slot)) }
        }
        for w in f.wearLog { c.insert(WearLog(outfitId: w.outfitId, itemIds: w.itemIds, date: w.date)) }
        try c.save()
        return added
    }
}

/// Settings numbers: item and outfit counts, AI calls in the last 7 days, median tagging time (calls tagA, tagB, tagC; successful only).
struct SettingsStats: Equatable {
    var items = 0, outfits = 0, aiCallsThisWeek = 0
    var medianTaggingSeconds: Double?

    static func compute(in c: ModelContext, now: Date = .now) -> SettingsStats {
        let logs = (try? c.fetch(FetchDescriptor<AIRequestLog>())) ?? []
        let week = logs.filter { now.timeIntervalSince($0.createdAt) <= 7 * 86_400 && $0.createdAt <= now }
        let tag = week.filter { $0.purpose.hasPrefix("tag") && $0.success }.map(\.durationSeconds).sorted()
        let median: Double? = tag.isEmpty ? nil : tag.count % 2 == 1 ? tag[tag.count / 2] : (tag[tag.count / 2 - 1] + tag[tag.count / 2]) / 2
        return SettingsStats(items: (try? c.fetchCount(FetchDescriptor<Item>())) ?? 0,
                             outfits: (try? c.fetchCount(FetchDescriptor<Outfit>())) ?? 0,
                             aiCallsThisWeek: week.count, medianTaggingSeconds: median)
    }
}
