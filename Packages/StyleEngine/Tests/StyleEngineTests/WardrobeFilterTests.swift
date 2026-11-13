import Foundation
import Testing
@testable import StyleEngine

private func snap(_ name: String, cat: Category, sub: Subcategory = .shirt, colours: [String] = [], codes: [DressCode] = [],
                  seasons: [Season] = [], brand: String? = nil, sub2: String? = nil, caption: String = "") -> WardrobeFilter.Snapshot {
    var t = ItemTags(); t.category = cat; t.subcategory = sub; t.dressCodes = codes; t.seasons = seasons
    return .init(id: UUID(), name: name, caption: caption, tags: t, colourNames: colours, brand: brand, subBrand: sub2)
}

private let rust = snap("Rust mandarin shirt", cat: .top, colours: ["rust"], codes: [.casual, .festive], caption: "Crinkled linen")
private let navyTee = snap("Navy tee", cat: .top, sub: .tshirt, colours: ["navy"], codes: [.casual])
private let blackJeans = snap("Black jeans", cat: .bottom, sub: .jeans, colours: ["black"], codes: [.casual], brand: "Westside", sub2: "WES")
private let all = [rust, navyTee, blackJeans]
private func names(_ f: WardrobeFilter) -> [String] { f.apply(to: all).map(\.name) }

@Test func S2_U24_oneFilter() {
    var f = WardrobeFilter(); f.categories = [.top]
    #expect(names(f) == ["Rust mandarin shirt", "Navy tee"])
}
@Test func S2_U25_orWithinField() {
    var f = WardrobeFilter(); f.colours = ["navy", "black"]
    #expect(names(f) == ["Navy tee", "Black jeans"])
}
@Test func S2_U26_andAcrossFields() {
    var f = WardrobeFilter(); f.categories = [.top]; f.dressCodes = [.festive]
    #expect(names(f) == ["Rust mandarin shirt"])
}
@Test func S2_U27_mergedTags() {
    // snapshot tags are already effective (Item.tags merges aiRaw < label < override)
    var raw = ItemTags(); raw.category = .top; raw.dressCodes = [.casual]
    var over = ItemTags(); over.dressCodes = [.festive]
    let item = WardrobeFilter.Snapshot(id: UUID(), name: "x", caption: "", tags: raw.overlaid(with: over), colourNames: [], brand: nil, subBrand: nil)
    var f = WardrobeFilter(); f.dressCodes = [.festive]
    #expect(f.apply(to: [item]).count == 1)
    f.dressCodes = [.casual]
    #expect(f.apply(to: [item]).isEmpty)
}
@Test func S2_U28_search() {
    var f = WardrobeFilter(); f.text = "MANDARIN"
    #expect(names(f) == ["Rust mandarin shirt"])
    f.text = "crinkled"
    #expect(names(f) == ["Rust mandarin shirt"])
    f.text = ""
    #expect(names(f).count == 3)
    f.text = "   "
    #expect(names(f).count == 3)
}
@Test func S2_brandFilter() {
    var f = WardrobeFilter(); f.brands = ["Westside"]
    #expect(names(f) == ["Black jeans"])
}
@Test func S2_searchBrandSubBrandSubcategoryColour() {
    var f = WardrobeFilter(); f.text = "westside"
    #expect(names(f) == ["Black jeans"])
    f.text = "wes"
    #expect(names(f) == ["Black jeans"])
    f.text = "T-shirt"
    #expect(names(f) == ["Navy tee"])
    f.text = "rust"
    #expect(names(f) == ["Rust mandarin shirt"])
}
@Test func S2_isActiveAndClear() {
    var f = WardrobeFilter()
    #expect(!f.isActive)
    f.seasons = [.summer]; #expect(f.isActive)
    f.clear(); #expect(!f.isActive)
}
