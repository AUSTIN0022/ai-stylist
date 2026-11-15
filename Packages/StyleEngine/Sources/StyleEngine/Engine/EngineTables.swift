import Foundation

// Occasion and colour tables, as data (PRD §5.4, Sprint 3 spec). Tuning means editing these literals.

/// A blocking rule on a single item. Occasions and intent flags list these; the engine never branches on occasion.
public enum ItemRule: String, Codable, CaseIterable, Sendable {
    case noGraphic, noSlides, noDenim, noShorts, noSleeveless, closedToeOnly, plainOrSubtle, noFormalShoes
}

/// A soft preference: items matching it score higher on occasionFit.
public enum Boost: String, Codable, CaseIterable, Sendable {
    case fittedTops, darkBottoms, warmColours, earthColours, lightColours, indian, indoWestern, indianSets, statementPiece
}

public struct OccasionRules: Sendable {
    public let dressCodes: [DressCode]          // first one is the primary
    public let formality: ClosedRange<Int>
    public var rules: [ItemRule] = []
    public var ifFlag: [IntentFlag: [ItemRule]] = [:]
    public var boosts: [Boost] = []
}

public enum OccasionTable {
    public static let rows: [Occasion: OccasionRules] = [
        .home: .init(dressCodes: [.home, .casual], formality: 1...2),
        .casualDay: .init(dressCodes: [.casual, .smartCasual], formality: 1...3),
        .office: .init(dressCodes: [.smartCasual, .businessCasual], formality: 3...4, rules: [.noGraphic, .noSlides]),
        .interview: .init(dressCodes: [.businessCasual, .formal], formality: 4...5, rules: [.plainOrSubtle, .closedToeOnly]),
        .date: .init(dressCodes: [.smartCasual, .party], formality: 3...4, boosts: [.fittedTops, .darkBottoms]),
        .party: .init(dressCodes: [.party, .smartCasual], formality: 2...4, boosts: [.statementPiece]),
        .festival: .init(dressCodes: [.festive, .smartCasual], formality: 3...4,
                         boosts: [.warmColours, .earthColours, .indian, .indoWestern]),
        .puja: .init(dressCodes: [.festive, .smartCasual], formality: 3...4, rules: [.noGraphic], boosts: [.indian, .lightColours]),
        .weddingGuest: .init(dressCodes: [.festive, .formal], formality: 4...5, rules: [.noDenim], boosts: [.indianSets, .indian]),
        .travel: .init(dressCodes: [.casual], formality: 1...3, ifFlag: [.lotsOfWalking: [.closedToeOnly]]),
        .gym: .init(dressCodes: [.athletic], formality: 1...1),
    ]
    /// Rules every occasion gets when the flag is set.
    public static let flagRules: [IntentFlag: [ItemRule]] = [
        .fireworks: [.closedToeOnly, .noSlides],
        .religiousSite: [.noShorts, .noSleeveless],
        .lotsOfWalking: [.noFormalShoes, .noSlides],
    ]
    /// Colour groups for boosts.
    public static let warmColours: Set<ColorName> = [.rust, .orange, .red, .mustard, .maroon, .yellow, .gold]
    public static let earthColours: Set<ColorName> = [.rust, .brown, .olive, .tan, .mustard, .maroon]
    public static let lightColours: Set<ColorName> = [.white, .cream, .beige, .lightBlue]
    public static let darkColours: Set<ColorName> = [.black, .navy, .charcoal, .brown, .maroon, .olive]
}

public enum ColourTable {
    public static let neutrals: Set<ColorName> = [.black, .white, .cream, .beige, .grey, .charcoal, .navy, .tan, .brown]
    /// Metals go with everything like neutrals do (not counted as an accent).
    public static let metallics: Set<ColorName> = [.gold, .silver]
    /// Neutrals where matching top and bottom is fine (tonal looks); other same-colour pairs are rejected.
    public static let tonalOK: Set<ColorName> = [.black, .white, .cream, .beige, .grey, .charcoal]
    /// Colours the same-colour check treats as one (navy knit and indigo jeans).
    public static let families: [Set<ColorName>] = [[.navy, .blue], [.rust, .orange], [.green, .olive]]

    static let good: [(ColorName, ColorName)] = [
        (.rust, .black), (.rust, .brown), (.olive, .cream), (.navy, .beige), (.lightBlue, .navy),
        (.maroon, .beige), (.mustard, .navy),
        (.rust, .olive), (.rust, .cream), (.olive, .brown), (.green, .beige),   // earth tones (PRD §5.5)
    ]
    static let clashes: [(ColorName, ColorName)] = [
        (.red, .pink), (.orange, .pink), (.red, .green), (.purple, .orange), (.orange, .red),
    ]
    private static func k(_ a: ColorName, _ b: ColorName) -> String {
        a.rawValue < b.rawValue ? a.rawValue + "|" + b.rawValue : b.rawValue + "|" + a.rawValue
    }
    private static let listed: [String: Double] = {
        var d: [String: Double] = [:]
        for (a, b) in good { d[k(a, b)] = 1.0 }
        for (a, b) in clashes { d[k(a, b)] = 0.1 }   // clashes win if a pair is in both
        return d
    }()

    static func soft(_ c: ColorName) -> Bool { neutrals.contains(c) || metallics.contains(c) }

    /// 0...1, symmetric. Listed pairs first, then neutral rules, then accent rules.
    public static func score(_ a: ColorName, _ b: ColorName) -> Double {
        if let v = listed[k(a, b)] { return v }
        switch (soft(a), soft(b)) {
        case (true, true): return 0.9
        case (true, false), (false, true): return 0.8
        default: return a == b || a == .multicolor || b == .multicolor ? 0.5 : 0.3
        }
    }

    /// True when top and bottom colours are the same non-tonal colour or family.
    public static func sameFamily(_ a: ColorName, _ b: ColorName) -> Bool {
        if a == b { return !tonalOK.contains(a) }
        return families.contains { $0.contains(a) && $0.contains(b) }
    }
}
