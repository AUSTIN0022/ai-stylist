import Testing
@testable import StyleEngine

private func shoe(_ sub: Subcategory, _ fabric: Fabric, _ codes: [DressCode]) -> ItemTags {
    var t = ItemTags(); t.category = .footwear; t.subcategory = sub; t.fabric = fabric; t.dressCodes = codes; return t
}

// 15 Nov: the AI called leather sneakers "Casual, Athletic".
@Test func S2_FX04_leatherSneakersAreNotAthletic() {
    #expect(shoe(.sneakers, .leather, [.casual, .athletic]).refined().dressCodes == [.casual])
    #expect(shoe(.sneakers, .suede, [.athletic, .smartCasual]).refined().dressCodes == [.smartCasual])
    #expect(shoe(.loafers, .leather, [.casual, .athletic]).refined().dressCodes == [.casual])
    #expect(shoe(.sneakers, .leather, [.athletic]).refined().dressCodes == [.casual])   // never left empty
}
@Test func S2_FX04b_otherItemsKeepAthletic() {
    #expect(shoe(.sneakers, .synthetic, [.casual, .athletic]).refined().dressCodes == [.casual, .athletic])
    var t = ItemTags(); t.category = .bottom; t.subcategory = .joggers; t.fabric = .leather; t.dressCodes = [.athletic]
    #expect(t.refined().dressCodes == [.athletic])
}
@Test func S2_FX03_fitIsAskedOnlyForGarments() {
    for c in [Category.top, .bottom, .onePiece, .outerwear] { #expect(asksFit(c)) }
    for c in [Category.footwear, .accessory] { #expect(!asksFit(c)) }
}
