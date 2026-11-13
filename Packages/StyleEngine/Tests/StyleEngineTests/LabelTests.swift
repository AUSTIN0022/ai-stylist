import Foundation
import Testing
@testable import StyleEngine

@Test func S1B_U24_fullLabel() {
    let l = LabelParser.parse(text: "WES\n100% ORGANIC COTTON\nSLIM FIT\nS", barcode: nil)
    #expect(l.brand == "Westside" && l.subBrand == "WES")
    #expect(l.composition == [FibrePart(percent: 100, fibre: "organic cotton")])
    #expect(l.fabric == .cotton && l.fit == .slim && l.size == "S")
}
@Test func S1B_U25_twoParts() {
    let l = LabelParser.parse(text: "60% Cotton 40% Polyester", barcode: nil)
    #expect(l.composition == [FibrePart(percent: 60, fibre: "cotton"), FibrePart(percent: 40, fibre: "polyester")])
    #expect(l.fabric == .cotton)
}
@Test func S1B_U26_synthetic() {
    #expect(LabelParser.parse(text: "65% Polyester 35% Viscose", barcode: nil).fabric == .synthetic)
}
@Test func S1B_U27_linenAndBlend() {
    #expect(LabelParser.parse(text: "100% Linen", barcode: nil).fabric == .linen)
    #expect(LabelParser.parse(text: "Cotton Linen", barcode: nil).fabric == .cottonLinen)
}
@Test func S1B_U28_mrp() {
    #expect(LabelParser.parse(text: "MRP ₹ 1,299.00 incl. of all taxes", barcode: nil).mrp == 1299)
    #expect(LabelParser.parse(text: "Rs.799", barcode: nil).mrp == 799)
}
@Test func S1B_U29_size() {
    #expect(LabelParser.parse(text: "Size: 32", barcode: nil).size == "32")
    #expect(LabelParser.parse(text: "Made in India", barcode: nil).size == nil)
    #expect(LabelParser.parse(text: "Wash with M care. Do not S bleach", barcode: nil).size == nil)
}
@Test func S1B_U30_fit() {
    #expect(LabelParser.parse(text: "Oversized Fit", barcode: nil).fit == .loose)
    #expect(LabelParser.parse(text: "Regular Fit", barcode: nil).fit == .regular)
}
@Test func S1B_U31_unknownBrand() {
    let l = LabelParser.parse(text: "Acme Garments\n100% Cotton\nSlim fit", barcode: nil)
    #expect(l.brand == nil && l.fabric == .cotton && l.fit == .slim)
}
@Test func S1B_U32_barcodeAndEmpty() {
    #expect(LabelParser.parse(text: "", barcode: "2050032266712").barcode == "2050032266712")
    let e = LabelParser.parse(text: "", barcode: nil)
    #expect(e == LabelData())
}
@Test func S1B_U33_labelOverridesAI() {
    var ai = ItemTags(); ai.fabric = .cotton
    var label = LabelData(); label.fabric = .linen
    #expect(ItemTags.effective(aiRaw: ai, label: label, userOverrides: ItemTags()).fabric == .linen)
}
@Test func S1B_U34_userOverridesLabel() {
    var label = LabelData(); label.fabric = .linen
    var user = ItemTags(); user.fabric = .wool
    #expect(ItemTags.effective(aiRaw: ItemTags(), label: label, userOverrides: user).fabric == .wool)
}
@Test func S1B_U35_removingOverrideRestoresLabel() {
    var label = LabelData(); label.fabric = .linen; label.fit = .slim
    var user = ItemTags(); user.fabric = .wool
    #expect(ItemTags.effective(aiRaw: ItemTags(), label: label, userOverrides: user).fabric == .wool)
    let t = ItemTags.effective(aiRaw: ItemTags(), label: label, userOverrides: ItemTags())
    #expect(t.fabric == .linen && t.fit == .slim)
}
@Test func S1B_U36_codableRoundTrip() throws {
    let l = LabelParser.parse(text: "WES\n60% Cotton 40% Polyester\nSlim fit\nMRP Rs. 999\nS", barcode: "123")
    let back = try JSONDecoder().decode(LabelData.self, from: JSONEncoder().encode(l))
    #expect(back == l)
}

// MARK: Round 2 (S1B-U37...U48)

private func parse(_ t: String, past: [String] = []) -> LabelData { LabelParser.parse(text: t, barcode: nil, pastBrands: past) }

@Test func S1B_U37_loneSizeLine() {
    let l = parse("WES\n100% ORGANIC COTTON\nSLIM FIT\nS")
    #expect(l.size == "S" && l.brand == "Westside")
}
@Test func S1B_U38_sizeForms() {
    #expect(parse("Size: M").size == "M")
    #expect(parse("SIZE M").size == "M")
    #expect(parse("M (38)").size == "M")
    #expect(parse("S/36").size == "S")
}
@Test func S1B_U39_doubleXL() {
    #expect(parse("2XL").size == "XXL")
    #expect(parse("3XL").size == "XXXL")
}
@Test func S1B_U40_sentenceIsNotSize() {
    #expect(parse("Wash a separately in cold water").size == nil)
    #expect(parse("Do not bleach S in water").size == nil)
}
@Test func S1B_U41_fuzzyBrand() {
    #expect(parse("WE5").brand == "Westside")
    #expect(parse("WFS").brand == "Westside")
    #expect(parse("Zaro").brand == "Zara")
    #expect(parse("Maximum comfort").brand == nil)
}
@Test func S1B_U42_pastBrandsFirst() {
    #expect(parse("SNITCH", past: ["Snitch"]).brand == "Snitch")
    #expect(parse("SN1TCH", past: ["Snitch"]).brand == "Snitch")
    #expect(parse("Nudie Jeans", past: ["Nudie Jeans"]).brand == "Nudie Jeans")   // not in the built-in list
}
@Test func S1B_U43_priceTag() {
    let l = parse("MRP ₹1,999\nSale Price ₹1,299\nColour: Olive\nStyle No: 300012345\nSize: L")
    #expect(l.mrp == 1999 && l.salePrice == 1299 && l.colour == "Olive" && l.styleCode == "300012345" && l.size == "L")
}
@Test func S1B_U44_mrpSanity() {
    #expect(parse("MRP ₹ 12").mrp == nil)
    #expect(parse("MRP ₹ 4,99,999").mrp == nil)
    #expect(parse("MRP ₹ 4,999").mrp == 4999)
}
@Test func S1B_U45_mergeLines() {
    let live = ["WES", "100% ORGANIC COTTON", "S"]
    let still = ["wes", "100% Organic Cotton", "SLIM FIT", "S", "MRP 999"]
    #expect(LabelParser.mergeLines(live: live, still: still) == ["WES", "100% ORGANIC COTTON", "S", "SLIM FIT", "MRP 999"])
}
@Test func S1B_U46_newFieldsRoundTripAndOldJSON() throws {
    var l = LabelData(); l.salePrice = 1299; l.colour = "Olive"; l.styleCode = "X1"
    #expect(try JSONDecoder().decode(LabelData.self, from: JSONEncoder().encode(l)) == l)
    let old = #"{"brand":"Zara","size":"M","mrp":999}"#.data(using: .utf8)!
    let d = try JSONDecoder().decode(LabelData.self, from: old)
    #expect(d.brand == "Zara" && d.size == "M" && d.salePrice == nil && d.colour == nil && d.styleCode == nil)
}
@Test func S1B_U47_sizeOptions() {
    let s = LabelOptions.sizes
    #expect(Array(s.prefix(8)) == ["XS", "S", "M", "L", "XL", "XXL", "XXXL", "Free size"])
    #expect(Array(s.dropFirst(8)) == (26...44).map(String.init))
}
@Test func S1B_U48_brandSuggestions() {
    #expect(LabelOptions.brandSuggestions(for: "we", past: ["Westside", "Zara"]).first == "Westside")
    let both = LabelOptions.brandSuggestions(for: "we", past: ["Wrangler Weekend", "Westside"])
    #expect(Array(both.prefix(2)) == ["Wrangler Weekend", "Westside"])   // past first, no duplicates
    #expect(LabelOptions.brandSuggestions(for: "", past: ["Snitch", "Nudie"]) == ["Snitch", "Nudie"])
    #expect(LabelOptions.brandSuggestions(for: "zar", past: []).contains("Zara"))
}

// MARK: Round 3 (S1B-U50...U54, I14 pure part)

@Test func S1B_U50_mergeLinesIgnoresCaseAndSpacing() {
    let m = LabelParser.mergeLines(live: ["100% ORGANIC COTTON"], still: ["100% organic  cotton", "SLIM FIT."])
    #expect(m == ["100% ORGANIC COTTON", "SLIM FIT."])
    #expect(LabelParser.mergeLines(live: ["Slim-Fit"], still: ["slim fit"]).count == 1)
}
@Test func S1B_U51_compositionPartsDeduplicated() {
    let l = LabelParser.parse(text: "100% organic cotton\n100% Organic Cotton", barcode: nil)
    #expect(l.composition == [FibrePart(percent: 100, fibre: "organic cotton")])
}
@Test func S1B_U52_neckLabelLoneDollarOrFiveIsS() {
    #expect(LabelParser.parse(text: "WES\n100% ORGANIC COTTON\nSLIM FIT\n$", barcode: nil).size == "S")
    #expect(LabelParser.parse(text: "WES\n100% ORGANIC COTTON\nSLIM FIT\n5", barcode: nil).size == "S")
    // never L from "1" or "l"-like noise
    #expect(LabelParser.parse(text: "WES\n100% ORGANIC COTTON\nSLIM FIT\n1", barcode: nil).size == nil)
}
@Test func S1B_U53_priceTagLoneFiveIsNotASize() {
    #expect(LabelParser.parse(text: "Westside\nMRP Rs. 799\n5", barcode: nil).size == nil)
    // too many lines for a neck label, even with a fit line
    #expect(LabelParser.parse(text: "a\nb\nc\nd\nSlim fit\ne\n5", barcode: nil).size == nil)
}
@Test func S1B_U54_rawTextRoundTripsAndOldJSONDecodes() throws {
    var l = LabelData(); l.rawText = "WES\nSLIM FIT"
    #expect(try JSONDecoder().decode(LabelData.self, from: JSONEncoder().encode(l)).rawText == "WES\nSLIM FIT")
    let old = #"{"brand":"Zara","size":"M"}"#.data(using: .utf8)!
    let d = try JSONDecoder().decode(LabelData.self, from: old)
    #expect(d.brand == "Zara" && d.rawText == nil)
    #expect(LabelParser.parse(text: "WES\nSLIM FIT", barcode: nil).rawText == "WES\nSLIM FIT")
}
@Test func S1B_I14_alternativesStayInCategory() {
    let alts = identityAlternatives(for: .tshirt, in: .top)
    #expect(alts.count == 2 && !alts.contains(.tshirt) && alts.allSatisfy { subcategories(for: .top).contains($0) })
    for c in Category.allCases {
        for s in subcategories(for: c) {
            let a = identityAlternatives(for: s, in: c)
            #expect(a.count <= 2 && !a.contains(s) && a.allSatisfy { subcategories(for: c).contains($0) })
        }
    }
    // an AI answer from the wrong category still only offers the category's own subcategories
    #expect(identityAlternatives(for: .jeans, in: .top).allSatisfy { subcategories(for: .top).contains($0) })
}

// MARK: Brand catalog (S1B-U55...U65)

@Test func S1B_U55_wesSubBrand() {
    let l = parse("WES")
    #expect(l.brand == "Westside" && l.subBrand == "WES")
}
@Test func S1B_U56_nuon() {
    let l = parse("NUON")
    #expect(l.brand == "Westside" && l.subBrand == "Nuon")
}
@Test func S1B_U57_bombayPaisley() {
    let l = parse("BOMBAY PAISLEY")
    #expect(l.brand == "Westside" && l.subBrand == "Bombay Paisley")
}
@Test func S1B_U58_dnmx() {
    let l = parse("the dnmx")
    #expect(l.brand == "Reliance Trends" && l.subBrand == "DNMX")
}
@Test func S1B_U59_roadster() {
    let l = parse("ROADSTER")
    #expect(l.brand == "Myntra" && l.subBrand == "Roadster")
}
@Test func S1B_U60_noParent() {
    let l = parse("Allen Solly")
    #expect(l.brand == "Allen Solly" && l.subBrand == nil)
}
@Test func S1B_U61_lineOnlyWords() {
    #expect(parse("ONLY").brand == "Only")
    #expect(parse("Only the best").brand == nil)
    #expect(parse("MAXIMUM COMFORT").brand == nil)
    #expect(parse("CODE: 1234").brand == nil)
    #expect(parse("Style Code: 123").brand == nil)
}
@Test func S1B_U62_longestAlias() {
    #expect(parse("LEVIS STRAUSS & CO").brand == "Levi's")
    #expect(parse("POLO RALPH LAUREN").brand == "Ralph Lauren")
    #expect(parse("JACK & JONES").brand == "Jack & Jones")
}
@Test func S1B_U63_catalogLoads() {
    let e = BrandCatalog.shared.entries
    #expect(e.count >= 180)
    #expect(Set(e.map { $0.name.lowercased() }).count == e.count)
}
@Test func S1B_U64_lineOnlyLowercase() {
    for b in BrandCatalog.shared.entries { for a in b.lineOnly { #expect(a == a.lowercased(), "\(b.name): \(a)") } }
}
@Test func S1B_U65_suggestionsWithSubBrands() {
    let s = LabelOptions.brandSuggestions(for: "we", past: ["Wrangler Weekend"])
    #expect(s.first == "Wrangler Weekend")
    let wes = s.firstIndex(of: "WES · Westside"), west = s.firstIndex(of: "Westside"), ward = s.firstIndex(of: "Wardrobe · Westside")
    #expect(wes != nil && west != nil && ward != nil)
    if let wes, let west, let ward { #expect(wes < west && west < ward) }   // exact-prefix names before the rest
    #expect(Set(s).count == s.count)
    #expect(LabelOptions.split("WES · Westside") == ("Westside", "WES"))
    #expect(LabelOptions.split("Zara") == ("Zara", nil))
}
