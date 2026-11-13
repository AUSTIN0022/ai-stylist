import Foundation
import Testing
@testable import StyleEngine

private func tags(_ f: (inout ItemTags) -> Void) -> ItemTags { var t = ItemTags(); f(&t); return t }

// MARK: raw vs corrections (S2-U01..U07 pure part)
@Test func S2_U01_overrideWins() {
    let raw = tags { $0.fabric = .cotton }
    let o = ItemTags().settingOverride(\.fabric, to: .linen, raw: raw)
    #expect(raw.overlaid(with: o).fabric == .linen)
}
@Test func S2_U02_noOverride() { #expect(tags { $0.fabric = .cotton }.overlaid(with: ItemTags()).fabric == .cotton) }
@Test func S2_U03_overrideRemoved() {
    let raw = tags { $0.fabric = .cotton }
    let o = ItemTags().settingOverride(\.fabric, to: .linen, raw: raw).settingOverride(\.fabric, to: nil, raw: raw)
    #expect(o == ItemTags() && raw.overlaid(with: o).fabric == .cotton)
}
@Test func S2_U04_sameAsRawClearsOverride() {
    let raw = tags { $0.fabric = .cotton; $0.dressCodes = [.casual, .festive] }
    let o = ItemTags().settingOverride(\.fabric, to: .linen, raw: raw).settingOverride(\.fabric, to: .cotton, raw: raw)
    #expect(o.fabric == nil)
    // a set equal to the raw one in another order is also "the same"
    let d = ItemTags().settingOverride(\.dressCodes, to: [.festive, .casual], raw: raw)
    #expect(d.dressCodes == nil)
}
@Test func S2_U06_emptyDressCodesRejected() {
    let raw = tags { $0.dressCodes = [.casual] }
    let before = ItemTags().settingOverride(\.dressCodes, to: [.formal], raw: raw)
    let after = before.settingOverride(\.dressCodes, to: [], raw: raw)
    #expect(after == before && after.dressCodes == [.formal])
}

// MARK: tag type (S2-U08, U09)
@Test func S2_U08_roundTrip() throws {
    let t = tags { $0.category = .top; $0.fabric = .linen; $0.dressCodes = [.casual, .festive]; $0.formality = 2; $0.warmth = 1; $0.caption = "x" }
    #expect(try JSONDecoder().decode(ItemTags.self, from: JSONEncoder().encode(t)) == t)
}
@Test func S2_U09_missingFieldsDecode() throws {
    let t = try JSONDecoder().decode(ItemTags.self, from: Data(#"{"category":"footwear","fabric":"leather","closedToe":true}"#.utf8))
    #expect(t.collar == nil && t.sleeve == nil && t.closedToe == true)
}

// MARK: auto-name (S2-U10, U11)
@Test func S2_U10_autoName() {
    #expect(ItemNaming.autoName(color: .rust, tags: tags { $0.subcategory = .shirt; $0.collar = .mandarin; $0.fabric = .linen }) == "Rust mandarin-collar linen shirt")
    #expect(ItemNaming.autoName(color: .black, tags: tags { $0.subcategory = .chinos; $0.fit = .relaxed }) == "Black relaxed chinos")
    #expect(ItemNaming.autoName(color: .cream, tags: tags { $0.subcategory = .sweater; $0.fabric = .knit }) == "Cream knit sweater")
    #expect(ItemNaming.autoName(color: .navy, tags: tags { $0.subcategory = .tshirt; $0.fabric = .cottonLinen }) == "Navy cotton-linen t-shirt")
    #expect(ItemNaming.autoName(color: .maroon, tags: tags { $0.subcategory = .lehengaSkirt }) == "Maroon lehenga skirt")
}
@Test func S2_U11_unknownsLeftOut() {
    #expect(ItemNaming.autoName(color: .white, tags: tags { $0.subcategory = .shirt; $0.fabric = .unknown; $0.collar = Collar.none }) == "White shirt")
    #expect(ItemNaming.autoName(color: nil, tags: tags { $0.subcategory = .shirt }) == "Shirt")
    #expect(ItemNaming.autoName(color: .red, tags: ItemTags()) == "Red item")
}

// MARK: call B fields (S2-U13)
@Test func S2_U13_callBFieldsFollowCategory() {
    #expect(constructionFields(for: .top) == [.collar, .sleeve, .fit, .length, .fabric, .pattern])
    #expect(constructionFields(for: .bottom) == [.fit, .length, .fabric, .pattern])
    #expect(constructionFields(for: .footwear) == [.fabric, .closedToe])
    #expect(constructionFields(for: .accessory) == [.fabric])
    for c in Category.allCases { #expect(constructionFields(for: c).isSubset(of: fields(for: c))) }
}
@Test func S2_U13b_answerStructsOnlyFillTheirFields() {
    let top = TopConstruction(fabric: .linen, pattern: .solid, fit: .relaxed, length: .long, collar: .mandarin, sleeve: .long).tags
    #expect(top.collar == .mandarin && top.sleeve == .long && top.length == .long && top.closedToe == nil)
    let bottom = BottomConstruction(fabric: .cotton, pattern: .solid, fit: .slim, length: .cropped).tags
    #expect(bottom.length == nil, "a top length is not valid for bottoms")   // sanitised
    #expect(bottom.collar == nil && bottom.sleeve == nil && bottom.fit == .slim)
    let shoe = FootwearConstruction(fabric: .leather, closedToe: true).tags
    #expect(shoe == tags { $0.fabric = .leather; $0.closedToe = true })
    let acc = AccessoryConstruction(fabric: .unknown).tags
    #expect(acc == tags { $0.fabric = .unknown })
    #expect(constructionFields(for: .onePiece).contains(.collar))
    #expect(construction(for: .footwear, in: shoe) == shoe)
}
@Test func S2_U13c_usageMapping() {
    let t = UsageTags(dressCodes: [.casual, .smartCasual], formality: 3, seasons: [.summer], warmth: 1, statement: .plain, caption: "A rust shirt").tags
    #expect(t.dressCodes == [.casual, .smartCasual] && t.formality == 3 && t.warmth == 1 && t.statement == .plain && t.caption == "A rust shirt")
}

// MARK: accuracy (S2-U30...)
private func sample(_ id: String, raw: ItemTags, effective eff: ItemTags, scan: LabelData? = nil, label: LabelData? = nil) -> AccuracySample {
    AccuracySample(id: id, aiRaw: raw, effective: eff, labelScan: scan, label: label)
}

@Test func S2_U30_changedFieldIsMiss() {
    let raw = tags { $0.category = .top; $0.fabric = .cotton; $0.pattern = .solid }
    let eff = tags { $0.category = .top; $0.fabric = .linen; $0.pattern = .solid }
    let r = WardrobeAccuracy.report([sample("a", raw: raw, effective: eff)])
    #expect(r.accuracy("fabric") == 0 && r.accuracy("pattern") == 100 && r.accuracy("category") == 100)
    #expect(r.wrong.contains { $0.id == "a" && $0.field == "fabric" })
}
@Test func S2_U31_notApplicableNotScored() {
    // shoes: no collar or sleeve either side
    let shoe = tags { $0.category = .footwear; $0.fabric = .leather }
    let r = WardrobeAccuracy.report([sample("s", raw: shoe, effective: shoe)])
    #expect(r.accuracy("collar") == nil && r.accuracy("fabric") == 100)
    // the AI left a field empty and the user filled it: a miss
    let r2 = WardrobeAccuracy.report([sample("s", raw: tags { $0.category = .top }, effective: tags { $0.category = .top; $0.collar = .polo })])
    #expect(r2.accuracy("collar") == 0)
}
@Test func S2_U32_dressCodeFirstValueRule() {
    let raw = tags { $0.dressCodes = [.casual, .festive] }
    let r1 = WardrobeAccuracy.report([sample("a", raw: raw, effective: tags { $0.dressCodes = [.festive, .party] })])
    #expect(r1.accuracy("dressCodes") == 100)   // first effective value is in the AI's list
    let r2 = WardrobeAccuracy.report([sample("a", raw: raw, effective: tags { $0.dressCodes = [.formal] })])
    #expect(r2.accuracy("dressCodes") == 0)
}
@Test func S2_U33_passMarksFabric75() {
    #expect(WardrobeAccuracy.marks["fabric"] == 75 && WardrobeAccuracy.marks["category"] == 95 && WardrobeAccuracy.marks["dressCodes"] == 80)
    // 3 of 4 fabric right = 75% passes; 2 of 3 = 66.7% fails
    func fabricReport(right: Int, of n: Int) -> WardrobeAccuracy.Report {
        WardrobeAccuracy.report((0..<n).map { i in
            let raw = tags { $0.fabric = .cotton }, eff = tags { $0.fabric = i < right ? .cotton : .linen }
            return sample("\(i)", raw: raw, effective: eff)
        })
    }
    #expect(fabricReport(right: 3, of: 4).result.passed.contains("fabric"))
    #expect(fabricReport(right: 2, of: 3).result.failed.contains("fabric"))
}
@Test func S2_U34_labelReadAccuracy() {
    var scan = LabelData(); scan.brand = "Westside"; scan.size = "S"; scan.fit = .slim; scan.mrp = 599
    var edited = scan; edited.size = "M"                       // user fixed the size
    let same = sample("a", raw: ItemTags(), effective: ItemTags(), scan: scan, label: edited)
    let none = sample("b", raw: ItemTags(), effective: ItemTags())   // no label: not counted
    let r = WardrobeAccuracy.report([same, none])
    #expect(r.labelItems == 1)
    #expect(r.labelFields["size"] == .init(right: 0, scored: 1))
    #expect(r.labelFields["brand"] == .init(right: 1, scored: 1))
    #expect(r.labelAccuracy == 75)    // brand, fit, mrp right; size wrong
}
@Test func S2_U35_emptyReportAndMarkdown() {
    let empty = WardrobeAccuracy.report([])
    #expect(empty.itemCount == 0 && empty.accuracy("category") == nil)
    let raw = tags { $0.category = .top; $0.fabric = .cotton }
    let md = WardrobeAccuracy.markdown(WardrobeAccuracy.report([sample("a", raw: raw, effective: tags { $0.category = .top; $0.fabric = .linen })]), date: "2026-11-20")
    #expect(md.contains("| field | accuracy | pass mark | pass? |"))
    #expect(md.contains("| category | 100.0% | 95% | pass |"))
    #expect(md.contains("| fabric | 0.0% | 75% | FAIL |"))
    #expect(md.contains("| collar | n/a | 85% | n/a |"))
    #expect(md.contains("| photo id | field | expected | got |") && md.contains("| a | fabric | linen | cotton |"))
}
@Test func S2_U36_onlyItemsWithAiRawCount() {
    let r = WardrobeAccuracy.report([sample("a", raw: tags { $0.category = .top }, effective: tags { $0.category = .top })])
    #expect(r.itemCount == 1)
}
