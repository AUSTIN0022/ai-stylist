import Foundation
import Testing
@testable import StyleEngine

// The E-ENG rating sheet (SPRINT_6_TESTS.md): ten occasions, the top three each, wear / wouldn't wear with a reason.

@Suite("S6 rating sheet") struct RatingSheetTests {
    @Test("ten occasions, each answered with three outfits on the fixture wardrobe") func requests() throws {
        #expect(RatingSheet.requests.count == 10)
        #expect(Set(RatingSheet.requests.map(\.title)).count == 10)
        let f = try loadFixture()
        for r in RatingSheet.requests {
            #expect(OutfitEngine.generate(intent: r.intent, items: f.items, context: RatingSheet.context).outfits.count == 3, "\(r.title)")
        }
    }

    @Test("wearable count and the pass rule (at least 2 of 3)") func passRule() {
        func row(_ r: [Rating?]) -> RatingSheet.Row { .init(title: "t", outfits: r.map { .init(description: "o", rating: $0, reason: "") }) }
        #expect(row([.wear, .wear, .wouldNot]).wearable == 2 && row([.wear, .wear, .wouldNot]).passes)
        #expect(!row([.wear, .wouldNot, .wouldNot]).passes)
        #expect(!row([.wear, .wear, nil]).isComplete)
        #expect(row([.wear, .wear, .wouldNot]).isComplete)
        #expect(RatingSheet.passed([row([.wear, .wear, .wear]), row([.wear, .wear, .wear])]) == 2)
    }

    @Test("markdown has a row per occasion with its count, and the reasons for each no") func markdown() {
        let rows: [RatingSheet.Row] = [
            .init(title: "Office", outfits: [.init(description: "A + B", rating: .wear, reason: ""),
                                             .init(description: "C + D", rating: .wouldNot, reason: "too plain"),
                                             .init(description: "E + F", rating: .wear, reason: "")]),
        ]
        let md = RatingSheet.markdown(rows, round: "Before tuning", date: "2026-12-01")
        #expect(md.contains("Before tuning") && md.contains("Office") && md.contains("2/3"))
        #expect(md.contains("too plain"))
        #expect(md.contains("1 of 1 occasions pass"))
    }

    @Test("reasons are grouped so the fix location is clear") func reasons() {
        #expect(RatingSheet.group(for: "too plain") == "Colour table")
        #expect(RatingSheet.group(for: "Too formal") == "Occasion table: formality range")
        #expect(RatingSheet.group(for: "wrong shoes") == "Footwear rules and formalityMatch weight")
        #expect(RatingSheet.group(for: "clash") == "Colour table clash list")
        #expect(RatingSheet.group(for: "always the same") == "Diversity: variety and freshness weights")
        #expect(RatingSheet.group(for: "mis-tagged") == "Not the engine: fix the tag")
        #expect(RatingSheet.group(for: "purple") == "Other")
    }
}
