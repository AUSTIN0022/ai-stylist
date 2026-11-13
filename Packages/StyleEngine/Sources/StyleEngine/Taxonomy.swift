import Foundation
import FoundationModels

// Fixed values for every tag field (PRD §5.3). Plain data tables: no UI, no AI calls.
// Raw values are stored in the database and in JSON. Never rename one (S1-U01 snapshot guards this).

public protocol Taxonomy: RawRepresentable, Sendable where RawValue == String {
    var displayName: String { get }
}

private let displayOverrides = [
    "tshirt": "T-shirt", "vNeck": "V-neck", "indoWestern": "Indo-western", "cottonLinen": "Cotton-linen",
]

public extension Taxonomy {
    /// "lightBlue" -> "Light blue"; a few irregular ones are overridden.
    var displayName: String {
        if let o = displayOverrides[rawValue] { return o }
        var out = ""
        for ch in rawValue {
            if ch.isUppercase { out += " " + ch.lowercased() } else { out.append(ch) }
        }
        return out.prefix(1).uppercased() + out.dropFirst()
    }
}

@Generable public enum Category: String, Codable, CaseIterable, Sendable, Taxonomy {
    case top, bottom, onePiece, outerwear, footwear, accessory
}

@Generable public enum Subcategory: String, Codable, CaseIterable, Sendable, Taxonomy {
    case shirt, tshirt, polo, sweater, hoodie, jacket, blazer, kurta, kurti, blouse, choli
    case jeans, chinos, trousers, shorts, joggers, pyjama, salwar, skirt, lehengaSkirt
    case dress, saree, dupatta
    case sneakers, boots, formalShoes, loafers, sandals, slides, heels, flats, juttis
    case belt, watch, chain, glasses, bag, cap, other
}

@Generable public enum StyleOrigin: String, Codable, CaseIterable, Sendable, Taxonomy {
    case western, indian, indoWestern
}

/// `none`, or a named part of a garment set. Items of one set share a `setGroupId`.
@Generable public enum SetRole: String, Codable, CaseIterable, Sendable, Taxonomy {
    case none, kurta, kurtaBottom, dupatta, lehengaSkirt, choli, saree, blouse
}

@Generable public enum ColorName: String, Codable, CaseIterable, Sendable, Taxonomy {
    case black, white, cream, beige, grey, charcoal, navy, blue, lightBlue, teal, green, olive
    case yellow, mustard, orange, rust, red, maroon, pink, purple, brown, tan, gold, silver, multicolor

    /// Reference colour used to name an extracted hex (nearest in Lab). `multicolor` has none.
    public var referenceHex: String? {
        switch self {
        case .black: "000000"
        case .white: "FFFFFF"
        case .cream: "F3EBDD"
        case .beige: "D9C7A7"
        case .grey: "9A9A9A"
        case .charcoal: "3A3A3A"
        case .navy: "1F2A44"
        case .blue: "2F5DA8"
        case .lightBlue: "9CC3E6"
        case .teal: "1F7A7A"
        case .green: "2E8B57"
        case .olive: "556B2F"
        case .yellow: "F2D43D"
        case .mustard: "C9A227"
        case .orange: "E8802A"
        case .rust: "B5522B"
        case .red: "C0272D"
        case .maroon: "800020"
        case .pink: "E88CA5"
        case .purple: "6A3D9A"
        case .brown: "6B4423"
        case .tan: "C19A6B"
        case .gold: "D4AF37"
        case .silver: "C0C0C0"
        case .multicolor: nil
        }
    }
}

@Generable public enum Pattern: String, Codable, CaseIterable, Sendable, Taxonomy {
    case solid, stripe, check, graphic, floral, embroidered, textured, colourBlock, other
}

@Generable public enum Fabric: String, Codable, CaseIterable, Sendable, Taxonomy {
    case cotton, linen, cottonLinen, denim, corduroy, twill, jersey, knit, wool, fleece
    case silk, satin, synthetic, leather, suede, unknown
}

@Generable public enum Fit: String, Codable, CaseIterable, Sendable, Taxonomy {
    case slim, regular, relaxed, loose, boxy
}

/// cropped/regular/long for tops; short/ankle/full for bottoms.
@Generable public enum Length: String, Codable, CaseIterable, Sendable, Taxonomy {
    case cropped, regular, long, short, ankle, full
}

@Generable public enum Collar: String, Codable, CaseIterable, Sendable, Taxonomy {
    case spread, buttonDown, mandarin, camp, polo, crew, vNeck, hooded, zipStand, none
}

@Generable public enum Sleeve: String, Codable, CaseIterable, Sendable, Taxonomy {
    case sleeveless, short, threeQuarter, long
}

@Generable public enum DressCode: String, Codable, CaseIterable, Sendable, Taxonomy {
    case home, casual, smartCasual, businessCasual, formal, festive, party, athletic
}

@Generable public enum Season: String, Codable, CaseIterable, Sendable, Taxonomy {
    case summer, monsoon, winter
}

@Generable public enum Statement: String, Codable, CaseIterable, Sendable, Taxonomy {
    case plain, medium, statement
}

// MARK: - Category rules

public enum TagField: String, Codable, CaseIterable, Sendable {
    case subcategory, styleOrigin, setRole, pattern, fabric, fit, length, collar, sleeve
    case dressCodes, formality, seasons, warmth, statement, closedToe
}

public func subcategories(for category: Category) -> [Subcategory] {
    switch category {
    case .top: [.shirt, .tshirt, .polo, .sweater, .hoodie, .kurta, .kurti, .blouse, .choli]
    case .bottom: [.jeans, .chinos, .trousers, .shorts, .joggers, .pyjama, .salwar, .skirt, .lehengaSkirt]
    case .onePiece: [.dress, .saree]
    case .outerwear: [.jacket, .blazer]
    case .footwear: [.sneakers, .boots, .formalShoes, .loafers, .sandals, .slides, .heels, .flats, .juttis]
    case .accessory: [.dupatta, .belt, .watch, .chain, .glasses, .bag, .cap, .other]
    }
}

/// Tag fields that apply to a category (footwear has no collar or sleeve; tops have no closedToe).
public func fields(for category: Category) -> Set<TagField> {
    let common: Set<TagField> = [.subcategory, .styleOrigin, .setRole, .pattern, .fabric,
                                 .dressCodes, .formality, .seasons, .warmth, .statement]
    switch category {
    case .top, .outerwear: return common.union([.fit, .length, .collar, .sleeve])
    case .onePiece: return common.union([.fit, .length, .collar, .sleeve])
    case .bottom: return common.union([.fit, .length])
    case .footwear: return common.union([.closedToe])
    case .accessory: return common
    }
}

/// The tags of one item, stored as one JSON blob (`aiRaw` and `userOverrides` are both this type).
/// Colours are not here: code writes them separately.
public struct ItemTags: Codable, Equatable, Sendable {
    public var category: Category?
    public var subcategory: Subcategory?
    public var styleOrigin: StyleOrigin?
    public var setRole: SetRole?
    public var pattern: Pattern?
    public var fabric: Fabric?
    public var fit: Fit?
    public var length: Length?
    public var collar: Collar?
    public var sleeve: Sleeve?
    public var dressCodes: [DressCode]?
    public var formality: Int?
    public var seasons: [Season]?
    public var warmth: Int?
    public var statement: Statement?
    public var closedToe: Bool?
    public var caption: String?

    public init() {}

    /// `self` overlaid with `overrides`: any field the user set wins.
    public func overlaid(with o: ItemTags) -> ItemTags {
        var r = self
        r.category = o.category ?? category; r.subcategory = o.subcategory ?? subcategory
        r.styleOrigin = o.styleOrigin ?? styleOrigin; r.setRole = o.setRole ?? setRole
        r.pattern = o.pattern ?? pattern; r.fabric = o.fabric ?? fabric; r.fit = o.fit ?? fit
        r.length = o.length ?? length; r.collar = o.collar ?? collar; r.sleeve = o.sleeve ?? sleeve
        r.dressCodes = o.dressCodes ?? dressCodes; r.formality = o.formality ?? formality
        r.seasons = o.seasons ?? seasons; r.warmth = o.warmth ?? warmth
        r.statement = o.statement ?? statement; r.closedToe = o.closedToe ?? closedToe
        r.caption = o.caption ?? caption
        return r
    }
}
