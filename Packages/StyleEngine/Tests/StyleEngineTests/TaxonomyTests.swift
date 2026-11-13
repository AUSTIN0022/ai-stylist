import Testing
import Foundation
@testable import StyleEngine

/// Raw values are stored in the database and in JSON blobs: renaming one breaks stored data.
/// This snapshot is PRD §5.3 verbatim. Change it only with a migration.
private let snapshot: [String: [String]] = [
    "Category": ["top", "bottom", "onePiece", "outerwear", "footwear", "accessory"],
    "Subcategory": ["shirt", "tshirt", "polo", "sweater", "hoodie", "jacket", "blazer", "kurta", "kurti", "blouse", "choli", "jeans", "chinos", "trousers", "shorts", "joggers", "pyjama", "salwar", "skirt", "lehengaSkirt", "dress", "saree", "dupatta", "sneakers", "boots", "formalShoes", "loafers", "sandals", "slides", "heels", "flats", "juttis", "belt", "watch", "chain", "glasses", "bag", "cap", "other"],
    "StyleOrigin": ["western", "indian", "indoWestern"],
    "SetRole": ["none", "kurta", "kurtaBottom", "dupatta", "lehengaSkirt", "choli", "saree", "blouse"],
    "ColorName": ["black", "white", "cream", "beige", "grey", "charcoal", "navy", "blue", "lightBlue", "teal", "green", "olive", "yellow", "mustard", "orange", "rust", "red", "maroon", "pink", "purple", "brown", "tan", "gold", "silver", "multicolor"],
    "Pattern": ["solid", "stripe", "check", "graphic", "floral", "embroidered", "textured", "colourBlock", "other"],
    "Fabric": ["cotton", "linen", "cottonLinen", "denim", "corduroy", "twill", "jersey", "knit", "wool", "fleece", "silk", "satin", "synthetic", "leather", "suede", "unknown"],
    "Fit": ["slim", "regular", "relaxed", "loose", "boxy"],
    "Length": ["cropped", "regular", "long", "short", "ankle", "full"],
    "Collar": ["spread", "buttonDown", "mandarin", "camp", "polo", "crew", "vNeck", "hooded", "zipStand", "none"],
    "Sleeve": ["sleeveless", "short", "threeQuarter", "long"],
    "DressCode": ["home", "casual", "smartCasual", "businessCasual", "formal", "festive", "party", "athletic"],
    "Season": ["summer", "monsoon", "winter"],
    "Statement": ["plain", "medium", "statement"],
]

private func rawValues<T: RawRepresentable & CaseIterable>(_ t: T.Type) -> [String] where T.RawValue == String {
    T.allCases.map(\.rawValue)
}

private let actual: [String: [String]] = [
    "Category": rawValues(Category.self), "Subcategory": rawValues(Subcategory.self),
    "StyleOrigin": rawValues(StyleOrigin.self), "SetRole": rawValues(SetRole.self),
    "ColorName": rawValues(ColorName.self), "Pattern": rawValues(Pattern.self),
    "Fabric": rawValues(Fabric.self), "Fit": rawValues(Fit.self), "Length": rawValues(Length.self),
    "Collar": rawValues(Collar.self), "Sleeve": rawValues(Sleeve.self),
    "DressCode": rawValues(DressCode.self), "Season": rawValues(Season.self),
    "Statement": rawValues(Statement.self),
]

@Test func S1_U01_rawValuesUniqueAndStable() {
    for (name, values) in actual {
        #expect(Set(values).count == values.count, "\(name) has duplicate raw values")
        #expect(values == snapshot[name], "\(name) raw values changed")
    }
    #expect(Set(actual.keys) == Set(snapshot.keys))
}

@Test func S1_U02_displayNames() {
    func check<T: CaseIterable & Taxonomy>(_ t: T.Type) {
        for c in T.allCases { #expect(!c.displayName.isEmpty) }
    }
    check(Category.self); check(Subcategory.self); check(StyleOrigin.self); check(SetRole.self)
    check(ColorName.self); check(Pattern.self); check(Fabric.self); check(Fit.self); check(Length.self)
    check(Collar.self); check(Sleeve.self); check(DressCode.self); check(Season.self); check(Statement.self)
    #expect(Subcategory.tshirt.displayName == "T-shirt")
    #expect(ColorName.lightBlue.displayName == "Light blue")
}

@Test func S1_U03_subcategoryMappingComplete() {
    var seen: [Subcategory: Category] = [:]
    for category in Category.allCases {
        for sub in subcategories(for: category) {
            #expect(seen[sub] == nil, "\(sub) in two categories")
            seen[sub] = category
        }
    }
    #expect(Set(seen.keys) == Set(Subcategory.allCases))
    #expect(subcategories(for: .footwear).contains(.juttis))
    #expect(subcategories(for: .onePiece).contains(.saree))
}

@Test func S1_U04_fieldsPerCategory() {
    let foot = fields(for: .footwear)
    #expect(foot.contains(.closedToe) && !foot.contains(.collar) && !foot.contains(.sleeve))
    let top = fields(for: .top)
    #expect(top.contains(.collar) && top.contains(.sleeve) && !top.contains(.closedToe))
    let acc = fields(for: .accessory)
    #expect(!acc.contains(.collar) && !acc.contains(.sleeve) && !acc.contains(.closedToe))
}

@Test func S1_U05_codableRoundTrip() throws {
    func roundTrip<T: CaseIterable & Codable & Equatable>(_ t: T.Type) throws {
        for c in T.allCases {
            let data = try JSONEncoder().encode([c])
            #expect(try JSONDecoder().decode([T].self, from: data) == [c])
        }
    }
    try roundTrip(Category.self); try roundTrip(Subcategory.self); try roundTrip(StyleOrigin.self)
    try roundTrip(SetRole.self); try roundTrip(ColorName.self); try roundTrip(Pattern.self)
    try roundTrip(Fabric.self); try roundTrip(Fit.self); try roundTrip(Length.self)
    try roundTrip(Collar.self); try roundTrip(Sleeve.self); try roundTrip(DressCode.self)
    try roundTrip(Season.self); try roundTrip(Statement.self)
}

@Test func itemTagsRoundTrip() throws {
    var t = ItemTags()
    t.category = .top; t.subcategory = .kurta; t.dressCodes = [.festive, .smartCasual]; t.formality = 4
    let back = try JSONDecoder().decode(ItemTags.self, from: JSONEncoder().encode(t))
    #expect(back == t)
}
