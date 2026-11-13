import Foundation
import StyleEngine
import SwiftData
import WardrobeImaging

// Objective-C (via Foundation) also declares `Category`; make ours win in the app module.
typealias Category = StyleEngine.Category

enum ItemStatus: String, Codable, Sendable { case tagging, ready, failed, archived }

/// One wardrobe item. Images are stored as file names only (see ImageStore); tags are one JSON blob each
/// for the AI's raw answer and the user's corrections; colours are separate because code writes them.
@Model final class Item {
    @Attribute(.unique) var id: UUID
    var createdAt: Date
    var status: ItemStatus
    var name: String
    var caption: String
    var aiRawData: Data?
    var userOverridesData: Data?
    var labelData: Data?          // JSON LabelData from a scanned label (optional: no store migration needed)
    var labelScanData: Data?      // the label exactly as the scanner parsed it, before the user's edits (for label accuracy)
    var hexColors: [String]
    var colorNames: [String]
    var setGroupId: UUID?
    var setRole: SetRole
    var originalFile: String
    var cutoutFile: String?
    var displayFile: String
    var taggerVersion: String?
    var lastWornAt: Date?
    var cutoutFailed: Bool
    var lastError: String?
    var featurePrintData: Data?   // filled in Sprint 6; declared now so the store never changes

    init(id: UUID = UUID(), originalFile: String, cutoutFile: String?, displayFile: String) {
        self.id = id; createdAt = .now; status = .tagging; name = ""; caption = ""
        hexColors = []; colorNames = []; setRole = .none
        self.originalFile = originalFile; self.cutoutFile = cutoutFile; self.displayFile = displayFile
        cutoutFailed = false
    }

    var label: LabelData? { labelData.flatMap { try? JSONDecoder().decode(LabelData.self, from: $0) } }
    var labelScan: LabelData? { labelScanData.flatMap { try? JSONDecoder().decode(LabelData.self, from: $0) } }
    /// The AI's answer, untouched. Written only by `replaceRaw`.
    var aiRaw: ItemTags { aiRawData.flatMap { try? JSONDecoder().decode(ItemTags.self, from: $0) } ?? ItemTags() }
    /// The user's corrections. Written only by `setOverride`.
    var userOverrides: ItemTags { userOverridesData.flatMap { try? JSONDecoder().decode(ItemTags.self, from: $0) } ?? ItemTags() }

    /// Effective tags: aiRaw < label < user corrections.
    var tags: ItemTags {
        func decode(_ d: Data?) -> ItemTags { d.flatMap { try? JSONDecoder().decode(ItemTags.self, from: $0) } ?? ItemTags() }
        return ItemTags.effective(aiRaw: decode(aiRawData), label: label, userOverrides: decode(userOverridesData))
    }
}

enum OutfitSource: String, Codable, Sendable { case ai, manual }

@Model final class Outfit {
    @Attribute(.unique) var id: UUID
    var name: String
    var source: OutfitSource
    var occasion: String?
    var note: String?
    var createdAt: Date
    var saved: Bool
    var canvasLayoutData: Data?   // per-item position and scale, manual outfits
    init(id: UUID = UUID(), name: String, source: OutfitSource) {
        self.id = id; self.name = name; self.source = source; createdAt = .now; saved = false
    }
}

@Model final class OutfitItem {
    var outfitId: UUID
    var itemId: UUID
    var slot: String
    init(outfitId: UUID, itemId: UUID, slot: String) { self.outfitId = outfitId; self.itemId = itemId; self.slot = slot }
}

@Model final class WearLog {
    var outfitId: UUID?
    var itemIds: [UUID]
    var date: Date
    init(outfitId: UUID? = nil, itemIds: [UUID], date: Date) { self.outfitId = outfitId; self.itemIds = itemIds; self.date = date }
}

@Model final class AIRequestLog {
    var purpose: String           // tagA, tagB, tagC, intent, note
    var provider: String
    var model: String
    var durationSeconds: Double
    var inputTokens: Int?
    var outputTokens: Int?
    var success: Bool
    var createdAt: Date
    var errorText: String?
    init(purpose: String, provider: String, model: String, durationSeconds: Double, inputTokens: Int? = nil,
         outputTokens: Int? = nil, success: Bool, createdAt: Date = .now, errorText: String? = nil) {
        self.purpose = purpose; self.provider = provider; self.model = model; self.durationSeconds = durationSeconds
        self.inputTokens = inputTokens; self.outputTokens = outputTokens; self.success = success; self.createdAt = createdAt
        self.errorText = errorText
    }
    convenience init(_ r: AICallRecord) {
        self.init(purpose: r.purpose, provider: r.provider, model: r.model, durationSeconds: r.seconds, inputTokens: nil,
                  outputTokens: r.tokens, success: r.success, createdAt: r.start, errorText: r.error)
    }
}

@Model final class FeedbackEvent {
    var outfitId: UUID
    var action: String            // saved, rejected, swapped
    var slot: String?
    var reason: String?
    var createdAt: Date
    init(outfitId: UUID, action: String, slot: String? = nil, reason: String? = nil, createdAt: Date = .now) {
        self.outfitId = outfitId; self.action = action; self.slot = slot; self.reason = reason; self.createdAt = createdAt
    }
}

extension Item {
    convenience init(_ p: ProcessedImages) {
        self.init(id: p.itemID, originalFile: p.originalFile, cutoutFile: p.cutoutFile, displayFile: p.displayFile)
        hexColors = p.hexColors
        colorNames = p.colorNames.map(\.rawValue)
        cutoutFailed = p.cutoutFailed
        lastError = p.lastError
    }

    /// The only place a user correction is written. nil or the AI's own value removes the override; an empty
    /// dress-code or season list is rejected. `aiRawData` is never touched.
    func setOverride<V: Equatable>(_ field: WritableKeyPath<ItemTags, V?>, to value: V?, context: ModelContext?) {
        let o = userOverrides.settingOverride(field, to: value, raw: aiRaw)
        userOverridesData = o == ItemTags() ? nil : try? JSONEncoder().encode(o)
        try? context?.save()
    }

    /// The only place `aiRaw` is written (queue, review save). Overrides stay as they are. The name follows the tags
    /// unless the user renamed the item (the current name no longer equals the one built from the old tags).
    func replaceRaw(_ raw: ItemTags, version: String, context: ModelContext?) {
        let before = tags
        aiRawData = try? JSONEncoder().encode(raw); taggerVersion = version
        if let c = raw.caption { caption = c }
        let color = colorNames.first.flatMap(ColorName.init(rawValue:))
        if name.isEmpty || name == ItemNaming.autoName(color: color, tags: before) { name = ItemNaming.autoName(color: color, tags: tags) }
        try? context?.save()
    }

    /// Saves edited label values (effective tags are unchanged except fabric/fit, which the label feeds).
    func setLabel(_ l: LabelData, context: ModelContext) {
        labelData = try? JSONEncoder().encode(l)
        try? context.save()
    }

    /// Rescan: new values and a new label.jpg replace the old ones.
    func replaceLabel(_ l: LabelData, jpeg: Data, store: ImageStore, context: ModelContext) {
        try? store.save(jpeg, named: ImageStore.labelName, for: id)
        setLabel(l, context: context)
    }

    /// Brands already in the wardrobe, once each, in the order given.
    static func pastBrands(_ items: [Item]) -> [String] {
        var seen = Set<String>()
        return items.compactMap { $0.label?.brand }.filter { seen.insert($0.lowercased()).inserted }
    }

    /// Removes the row and the item's image folder.
    @MainActor static func delete(_ item: Item, in context: ModelContext, store: ImageStore) {
        store.deleteItem(item.id)
        context.delete(item)
        try? context.save()
    }

    static let allModels: [any PersistentModel.Type] = [Item.self, Outfit.self, OutfitItem.self, WearLog.self, AIRequestLog.self, FeedbackEvent.self]
}
