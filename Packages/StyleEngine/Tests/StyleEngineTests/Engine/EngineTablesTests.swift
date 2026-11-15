import Foundation
import Testing
@testable import StyleEngine

@Suite("S3 fixture and tables") struct EngineTablesTests {
    @Test("S3-U01 fixture loads, 45 items, unique ids") func u01() throws {
        let f = try loadFixture()
        #expect(f.raw.count == 45)
        #expect(Set(f.raw.map(\.id)).count == 45)
        #expect(Set(f.raw.map(\.key)).count == 45)
    }
    @Test("S3-U02 fixture is complete") func u02() throws {
        for i in try loadFixture().raw {
            let t = i.tags
            #expect(t.category != nil && t.subcategory != nil, "\(i.key)")
            #expect(!i.colors.isEmpty, "\(i.key)")
            #expect(!(t.dressCodes ?? []).isEmpty, "\(i.key)")
            #expect((1...5).contains(t.formality ?? 0), "\(i.key)")
            #expect(!(t.seasons ?? []).isEmpty, "\(i.key)")
            #expect((1...3).contains(t.warmth ?? 0), "\(i.key)")
            #expect(t.statement != nil, "\(i.key)")
            #expect(i.lastWornAt == nil)
        }
    }
    @Test("fixture subcategories match their category") func subcategoriesValid() throws {
        for i in try loadFixture().raw {
            #expect(subcategories(for: i.tags.category!).contains(i.tags.subcategory!), "\(i.key)")
        }
    }
    @Test("fixture kurta set shares a group id, nofootwear fixture has no footwear") func sets() throws {
        let f = try loadFixture()
        #expect(f.item("kurta_mustard").setGroupId != nil)
        #expect(f.item("kurta_mustard").setGroupId == f.item("pyjama_cream").setGroupId)
        #expect(f.item("juttis_tan").setGroupId == nil)
        let nf = try loadFixture("wardrobe_nofootwear")
        #expect(!nf.raw.isEmpty && !nf.raw.contains { $0.tags.category == .footwear })
    }
    @Test("S3-U03 occasion table complete") func u03() {
        for o in Occasion.allCases {
            let r = OccasionTable.rows[o]
            #expect(r != nil, "\(o)")
            #expect(!(r?.dressCodes.isEmpty ?? true), "\(o)")
            if let r { #expect(r.formality.lowerBound <= r.formality.upperBound && r.formality.lowerBound >= 1 && r.formality.upperBound <= 5) }
        }
    }
    @Test("S3-U04 colour table symmetric and in 0-1") func u04() {
        for a in ColorName.allCases { for b in ColorName.allCases {
            #expect(ColourTable.score(a, b) == ColourTable.score(b, a), "\(a) \(b)")
            #expect((0...1).contains(ColourTable.score(a, b)))
        } }
        #expect(ColourTable.score(.rust, .black) == 1.0)
        #expect(ColourTable.score(.black, .white) == 0.9)
        #expect(ColourTable.score(.black, .teal) == 0.8)
        #expect(ColourTable.score(.teal, .mustard) == 0.3)
        #expect(ColourTable.score(.red, .pink) == 0.1)
    }
    @Test("S3-U05 weights sum to 1") func u05() {
        #expect(abs(ScoreWeights.standard.sum - 1.0) < 1e-9)
        #expect(ScoreWeights.standard.asDictionary.count == 6)
    }
    @Test("rows match the spec table") func rows() {
        #expect(OccasionTable.rows[.interview]?.formality == 4...5)
        #expect(OccasionTable.rows[.home]?.dressCodes == [.home, .casual])
        #expect(OccasionTable.rows[.gym]?.dressCodes == [.athletic])
        #expect(OccasionTable.rows[.weddingGuest]?.rules.contains(.noDenim) == true)
    }
}
