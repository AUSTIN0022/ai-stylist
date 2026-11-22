import Foundation

// Sprint 3: plain value types for the outfit engine. No SwiftData, no UI, no AI.

/// The engine's only wardrobe input. The app converts stored items (merged tags) to this.
public struct EngineItem: Sendable, Equatable {
    public let id: UUID
    public let name: String            // debug output only
    public let tags: ItemTags
    public let colors: [ColorName]     // primary colour first
    public let setGroupId: UUID?
    public let lastWornAt: Date?
    public let isReady: Bool           // false for tagging, failed or archived items
    public init(id: UUID = UUID(), name: String = "", tags: ItemTags, colors: [ColorName],
                setGroupId: UUID? = nil, lastWornAt: Date? = nil, isReady: Bool = true) {
        self.id = id; self.name = name; self.tags = tags; self.colors = colors
        self.setGroupId = setGroupId; self.lastWornAt = lastWornAt; self.isReady = isReady
    }
}

public enum Occasion: String, Codable, CaseIterable, Sendable {
    case casualDay, office, interview, date, party, weddingGuest, festival, puja, travel, gym, home
}
public enum TimeOfDay: String, Codable, CaseIterable, Sendable { case day, evening, night }
public enum VenueSetting: String, Codable, CaseIterable, Sendable { case indoor, outdoor, mixed }
public enum WeatherFeel: String, Codable, CaseIterable, Sendable { case hot, mild, cold, rainy, unknown }
public enum IntentFlag: String, Codable, CaseIterable, Sendable { case fireworks, lotsOfWalking, religiousSite, photoHeavy }
public enum AvoidTerm: Hashable, Codable, Sendable { case colour(ColorName), subcategory(Subcategory) }

/// PRD §5.4: what the intent parser produces and the engine consumes.
public struct OccasionIntent: Sendable, Equatable {
    public var occasion: Occasion
    public var dressCode: DressCode?
    public var formalityMin: Int?
    public var formalityMax: Int?
    public var timeOfDay: TimeOfDay
    public var setting: VenueSetting
    public var weatherFeel: WeatherFeel
    public var preferIndian: Bool
    public var flags: Set<IntentFlag>
    public var mustIncludeItemIds: [UUID]
    public var avoid: [AvoidTerm]
    public init(occasion: Occasion, dressCode: DressCode? = nil, formalityMin: Int? = nil, formalityMax: Int? = nil,
                timeOfDay: TimeOfDay = .day, setting: VenueSetting = .mixed, weatherFeel: WeatherFeel = .unknown,
                preferIndian: Bool = false, flags: Set<IntentFlag> = [], mustIncludeItemIds: [UUID] = [],
                avoid: [AvoidTerm] = []) {
        self.occasion = occasion; self.dressCode = dressCode; self.formalityMin = formalityMin
        self.formalityMax = formalityMax; self.timeOfDay = timeOfDay; self.setting = setting
        self.weatherFeel = weatherFeel; self.preferIndian = preferIndian; self.flags = flags
        self.mustIncludeItemIds = mustIncludeItemIds; self.avoid = avoid
    }
}

public enum Slot: String, Codable, CaseIterable, Sendable, Comparable {
    case top, baseLayer, bottom, onePiece, outerwear, footwear, accessory1, accessory2
    case setTop, setBottom, setDrape
    private var order: Int { Slot.allCases.firstIndex(of: self)! }
    public static func < (a: Slot, b: Slot) -> Bool { a.order < b.order }
}

public enum RejectReason: String, Codable, CaseIterable, Sendable {
    case notReady, avoided, wrongDressCode, formalityOutOfRange, wrongSeason, tooWarm
    case openToeBlocked, ruleBlocked, wornRecently
}

/// An unordered pair of item ids (saved-outfit pair weights).
public struct PairKey: Hashable, Sendable {
    public let a: UUID, b: UUID
    public init(_ x: UUID, _ y: UUID) { if x.uuidString <= y.uuidString { a = x; b = y } else { a = y; b = x } }
}

/// The set of item ids in an outfit, sorted so order never matters.
public struct OutfitKey: Hashable, Sendable {
    public let ids: [UUID]
    public init(_ ids: [UUID]) { self.ids = Array(Set(ids)).sorted { $0.uuidString < $1.uuidString } }
}

public struct EngineContext: Sendable {
    public var today: Date
    public var excludeOutfits: Set<OutfitKey>     // already shown
    public var pairWeights: [PairKey: Double]     // from saved outfits, empty for now
    public var excludeLooks: Set<[String]>        // looks already shown (see OutfitEngine.look); candidates only, not swaps
    public var seed: UInt64
    public init(today: Date = Date(), excludeOutfits: Set<OutfitKey> = [], pairWeights: [PairKey: Double] = [:], seed: UInt64 = 0,
                excludeLooks: Set<[String]> = []) {
        self.today = today; self.excludeOutfits = excludeOutfits; self.pairWeights = pairWeights; self.seed = seed
        self.excludeLooks = excludeLooks
    }
}

/// Six weights, one place, tuned in Sprint 6. They sum to 1.0.
public struct ScoreWeights: Sendable, Equatable {
    public var occasionFit = 0.30, colourHarmony = 0.25, formalityMatch = 0.15
    public var pairWeight = 0.15, freshness = 0.10, variety = 0.05
    public static let standard = ScoreWeights()
    public init() {}
    public var sum: Double { occasionFit + colourHarmony + formalityMatch + pairWeight + freshness + variety }
    /// Keys of `OutfitCandidate.scoreParts`.
    public var asDictionary: [String: Double] {
        ["occasionFit": occasionFit, "colourHarmony": colourHarmony, "formalityMatch": formalityMatch,
         "pairWeight": pairWeight, "freshness": freshness, "variety": variety]
    }
}

public struct OutfitCandidate: Sendable, Equatable {
    public let slots: [Slot: UUID]
    public let score: Double
    public let scoreParts: [String: Double]
    public init(slots: [Slot: UUID], score: Double, scoreParts: [String: Double]) {
        self.slots = slots; self.score = score; self.scoreParts = scoreParts
    }
    public var key: OutfitKey { OutfitKey(Array(slots.values)) }
    public var itemIds: [UUID] { key.ids }
}

public struct EngineResult: Sendable, Equatable {
    public let outfits: [OutfitCandidate]
    public let rejected: [UUID: RejectReason]
    public let missing: [Slot]          // why nothing was built; empty when outfits is not empty
    public let kept: [UUID]             // survivors of the filter stage (kept + rejected == input)
    public let softMissing: [Slot]      // built anyway without it (footwear): "add shoes to complete these looks"
}
