import Foundation

// Sprint 4: what the model says (all optional, nil = not mentioned) merged into a full OccasionIntent. Plain code, no AI.

/// The parser's answer. No pinned items: only the app's pin action sets `mustIncludeItemIds`.
public struct ParsedIntent: Sendable, Equatable {
    public var occasion: Occasion?, dressCode: DressCode?
    public var formalityMin: Int?, formalityMax: Int?
    public var timeOfDay: TimeOfDay?, setting: VenueSetting?, weatherFeel: WeatherFeel?
    public var preferIndian: Bool?
    public var flags: [IntentFlag]?
    public var avoid: [String]?
    public init(occasion: Occasion? = nil, dressCode: DressCode? = nil, formalityMin: Int? = nil, formalityMax: Int? = nil,
                timeOfDay: TimeOfDay? = nil, setting: VenueSetting? = nil, weatherFeel: WeatherFeel? = nil,
                preferIndian: Bool? = nil, flags: [IntentFlag]? = nil, avoid: [String]? = nil) {
        self.occasion = occasion; self.dressCode = dressCode; self.formalityMin = formalityMin; self.formalityMax = formalityMax
        self.timeOfDay = timeOfDay; self.setting = setting; self.weatherFeel = weatherFeel; self.preferIndian = preferIndian
        self.flags = flags; self.avoid = avoid
    }
}

public enum IntentMerge {
    /// Occasion chip: the table's values (nil dress code and formality mean "use the table"). No AI.
    public static func chipIntent(for o: Occasion) -> OccasionIntent {
        let evening: Set<Occasion> = [.date, .party, .weddingGuest, .festival]
        return OccasionIntent(occasion: o, timeOfDay: evening.contains(o) ? .evening : .day)
    }

    public static func pin(_ id: UUID, in intent: OccasionIntent) -> OccasionIntent {
        var i = intent
        if !i.mustIncludeItemIds.contains(id) { i.mustIncludeItemIds.append(id) }
        return i
    }

    /// Previous intent (or the table for the parsed occasion) with every mentioned field replaced.
    public static func merge(_ p: ParsedIntent, previous: OccasionIntent?, message: String) -> OccasionIntent {
        var i = previous ?? chipIntent(for: p.occasion ?? .casualDay)
        if let o = p.occasion, o != i.occasion {
            // New occasion: the old one's dress code and formality no longer apply.
            i.occasion = o; i.dressCode = nil; i.formalityMin = nil; i.formalityMax = nil
        }
        if let d = p.dressCode { i.dressCode = d }
        let row = OccasionTable.rows[i.occasion]?.formality ?? 1...5
        if p.formalityMin != nil || p.formalityMax != nil {
            var lo = p.formalityMin ?? i.formalityMin ?? row.lowerBound, hi = p.formalityMax ?? i.formalityMax ?? row.upperBound
            if p.formalityMax != nil && p.formalityMin == nil { lo = min(lo, hi) }
            if p.formalityMin != nil && p.formalityMax == nil { hi = max(hi, lo) }
            i.formalityMin = max(1, min(5, lo)); i.formalityMax = max(1, min(5, max(lo, hi)))
        }
        if let t = p.timeOfDay { i.timeOfDay = t }
        if let s = p.setting { i.setting = s }
        if let w = p.weatherFeel { i.weatherFeel = w }
        if let x = p.preferIndian { i.preferIndian = x }
        if let f = p.flags { i.flags.formUnion(f) }
        for t in (p.avoid ?? []).compactMap(avoidTerm) + keywordAvoid(in: message) where !i.avoid.contains(t) { i.avoid.append(t) }
        return i
    }

    // MARK: Avoid

    private static let synonyms: [String: AvoidTerm] = [
        "gray": .colour(.grey), "tee": .subcategory(.tshirt), "tees": .subcategory(.tshirt), "t-shirt": .subcategory(.tshirt),
        "t-shirts": .subcategory(.tshirt), "tshirts": .subcategory(.tshirt), "jean": .subcategory(.jeans), "pants": .subcategory(.trousers),
    ]
    /// "Black", "light blue", "jeans" -> a taxonomy value; anything else (free text) -> nil.
    public static func avoidTerm(_ text: String) -> AvoidTerm? {
        let w = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if let s = synonyms[w] { return s }
        let singular = w.hasSuffix("s") ? String(w.dropLast()) : w
        for c in ColorName.allCases where c != .multicolor && (c.rawValue.lowercased() == w || c.displayName.lowercased() == w) { return .colour(c) }
        for s in Subcategory.allCases where s != .other {
            let names = [s.rawValue.lowercased(), s.displayName.lowercased()]
            if names.contains(w) || names.contains(singular) { return .subcategory(s) }
        }
        return nil
    }

    /// Backstop for "no jeans", "not black", "without chinos", "avoid red": the word after the cue, if it is a taxonomy value.
    /// ponytail: one term per cue ("no black or navy" gets black only); extend if the model misses these.
    public static func keywordAvoid(in message: String) -> [AvoidTerm] {
        let cues: Set<String> = ["no", "not", "without", "avoid", "skip"]
        let words = message.lowercased().split(whereSeparator: { !($0.isLetter || $0 == "-") }).map(String.init)
        var out: [AvoidTerm] = []
        for (n, w) in words.enumerated() where cues.contains(w) && n + 1 < words.count {
            // "light blue" is two words: try the pair first.
            let next = [n + 2 < words.count ? words[n + 1] + " " + words[n + 2] : nil, words[n + 1]].compactMap { $0 }
            if let t = next.lazy.compactMap(avoidTerm).first, !out.contains(t) { out.append(t) }
        }
        return out
    }
}
