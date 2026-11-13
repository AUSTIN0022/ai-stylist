import FoundationModels

// Sprint 0 throwaway enums. Raw values are the PRD section 5.3 values, exactly.
// Sprint 1 adds the real enums (plain names) to the StyleEngine package.

@Generable enum SpikeCategory: String, CaseIterable {
    case top, bottom, onePiece, outerwear, footwear, accessory
}
@Generable enum SpikeSubcategory: String, CaseIterable {
    case shirt, tshirt, polo, sweater, hoodie, jacket, blazer, kurta, kurti, blouse, choli
    case jeans, chinos, trousers, shorts, joggers, pyjama, salwar, skirt, lehengaSkirt
    case dress, saree, dupatta, sneakers, boots, formalShoes, loafers, sandals, slides
    case heels, flats, juttis, belt, watch, chain, glasses, bag, cap, other
}
@Generable enum SpikeStyleOrigin: String, CaseIterable { case western, indian, indoWestern }
@Generable enum SpikePattern: String, CaseIterable {
    case solid, stripe, check, graphic, floral, embroidered, textured, colourBlock, other
}
@Generable enum SpikeFabric: String, CaseIterable {
    case cotton, linen, cottonLinen, denim, corduroy, twill, jersey, knit, wool, fleece
    case silk, satin, synthetic, leather, suede, unknown
}
@Generable enum SpikeFit: String, CaseIterable { case slim, regular, relaxed, loose, boxy }
@Generable enum SpikeCollar: String, CaseIterable {
    case spread, buttonDown, mandarin, camp, polo, crew, vNeck, hooded, zipStand, none
}
@Generable enum SpikeSleeve: String, CaseIterable { case sleeveless, short, threeQuarter, long }
@Generable enum SpikeDressCode: String, CaseIterable {
    case home, casual, smartCasual, businessCasual, formal, festive, party, athletic
}
@Generable enum SpikeSeason: String, CaseIterable { case summer, monsoon, winter }

/// Only used to validate expected.json; the model is never asked for colour.
enum SpikeColor: String, CaseIterable {
    case black, white, cream, beige, grey, charcoal, navy, blue, lightBlue, teal, green, olive
    case yellow, mustard, orange, rust, red, maroon, pink, purple, brown, tan, gold, silver, multicolor
}

/// Field name -> allowed values, for ExpectedFile.decode (S0-U10).
enum SpikeTaxonomy {
    static let allowed: [String: Set<String>] = [
        "category": values(SpikeCategory.self),
        "subcategory": values(SpikeSubcategory.self),
        "styleOrigin": values(SpikeStyleOrigin.self),
        "colors": values(SpikeColor.self),
        "pattern": values(SpikePattern.self),
        "fabric": values(SpikeFabric.self),
        "fit": values(SpikeFit.self),
        "collar": values(SpikeCollar.self),
        "sleeve": values(SpikeSleeve.self),
        "dressCodes": values(SpikeDressCode.self),
    ]
    /// Fields the eval scores (colour is not measured this sprint).
    static let scoredFields = ["category", "subcategory", "pattern", "fabric", "fit", "collar", "sleeve", "dressCodes"]

    private static func values<E: RawRepresentable & CaseIterable>(_ e: E.Type) -> Set<String> where E.RawValue == String {
        Set(E.allCases.map(\.rawValue))
    }
}

// MARK: Tagging call structs

@Generable struct SpikeIdentityTags {
    @Guide(description: "The main kind of clothing item shown")
    var category: SpikeCategory
    @Guide(description: "The specific type of item. A knitted pullover or zip knit is sweater. A collared short or long sleeve jersey top is polo.")
    var subcategory: SpikeSubcategory
    @Guide(description: "western for everyday Western clothes; indian for kurta, saree, lehenga; indoWestern for a mix")
    var styleOrigin: SpikeStyleOrigin
}

@Generable struct SpikeConstructionTags {
    @Guide(description: "Fabric, best guess from the look. Use unknown if unsure.")
    var fabric: SpikeFabric
    @Guide(description: "Surface pattern. solid means one plain colour.")
    var pattern: SpikePattern
    @Guide(description: "How loose the garment is cut")
    var fit: SpikeFit
    @Guide(description: "Collar or neckline. mandarin is a short stand-up band with no fold. spread is a folded collar with points apart. buttonDown has points buttoned to the shirt. polo is a soft knit collar. none for items without a neckline feature.")
    var collar: SpikeCollar
    @Guide(description: "Sleeve length. Use long for jackets, hoodies and sweaters with sleeves.")
    var sleeve: SpikeSleeve
}

@Generable struct SpikeUsageTags {
    @Guide(description: "Occasions this item suits, best match first", .maximumCount(3))
    var dressCodes: [SpikeDressCode]
    @Guide(description: "Formality from 1 (home wear) to 5 (formal)", .range(1...5))
    var formality: Int
    @Guide(description: "Seasons this item suits", .maximumCount(3))
    var seasons: [SpikeSeason]
    @Guide(description: "One short line describing the item")
    var caption: String
}
