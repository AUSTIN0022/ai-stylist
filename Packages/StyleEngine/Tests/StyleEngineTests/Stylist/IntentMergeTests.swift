import Foundation
import Testing
@testable import StyleEngine

@Suite("S4 intent merge") struct IntentMergeTests {
    let festival = OccasionIntent(occasion: .festival, timeOfDay: .evening, setting: .indoor)

    @Test("S4-U01 follow-up keeps unmentioned fields") func u01() {
        let out = IntentMerge.merge(ParsedIntent(formalityMax: 2), previous: festival, message: "make it more casual")
        #expect(out.occasion == .festival && out.timeOfDay == .evening && out.setting == .indoor)
        #expect(out.formalityMax == 2)
        #expect((out.formalityMin ?? 1) <= 2)
    }
    @Test("S4-U02 follow-up changes one field") func u02() {
        var prev = festival; prev.setting = .indoor
        let out = IntentMerge.merge(ParsedIntent(setting: .outdoor), previous: prev, message: "actually it's outdoors")
        var expected = prev; expected.setting = .outdoor
        #expect(out == expected)
    }
    @Test("S4-U03 first message uses the occasion table") func u03() {
        let out = IntentMerge.merge(ParsedIntent(occasion: .office), previous: nil, message: "office tomorrow")
        #expect(out.occasion == .office)
        #expect(out.dressCode == nil && out.formalityMin == nil && out.formalityMax == nil)   // nil = the table's values
        #expect(OccasionTable.rows[.office]!.dressCodes.contains(.businessCasual))
        #expect(out.mustIncludeItemIds.isEmpty)
    }
    @Test("S4-U03b nothing parsed and nothing before gives casual day") func u03b() {
        #expect(IntentMerge.merge(ParsedIntent(), previous: nil, message: "hmm").occasion == .casualDay)
    }
    @Test("S4-U04 avoid backstop from the message") func u04() {
        let out = IntentMerge.merge(ParsedIntent(avoid: []), previous: nil, message: "no jeans, not black")
        #expect(out.avoid.contains(.subcategory(.jeans)) && out.avoid.contains(.colour(.black)))
        let two = IntentMerge.merge(ParsedIntent(), previous: nil, message: "No chinos please")
        #expect(two.avoid == [.subcategory(.chinos)])
        #expect(IntentMerge.merge(ParsedIntent(), previous: nil, message: "no crackers, no worries").avoid.isEmpty)
    }
    @Test("S4-U05 avoid limited to known values") func u05() {
        let out = IntentMerge.merge(ParsedIntent(avoid: ["polyester vibes", "Black", "shirt"]), previous: nil, message: "x")
        #expect(out.avoid == [.colour(.black), .subcategory(.shirt)])
    }
    @Test("S4-U06 occasion chip intent comes from the table") func u06() {
        let i = IntentMerge.chipIntent(for: .festival)
        #expect(i.occasion == .festival && i.dressCode == nil && i.formalityMin == nil && i.avoid.isEmpty && i.mustIncludeItemIds.isEmpty)
        for o in Occasion.allCases { #expect(IntentMerge.chipIntent(for: o).occasion == o) }
    }
    @Test("S4-U07 pinned items never come from the parser") func u07() {
        let id = UUID()
        let pinned = IntentMerge.pin(id, in: festival)
        #expect(pinned.mustIncludeItemIds == [id] && IntentMerge.pin(id, in: pinned).mustIncludeItemIds == [id])
        // A follow-up keeps the app's pin; the parsed struct has no field for it.
        #expect(IntentMerge.merge(ParsedIntent(setting: .outdoor), previous: pinned, message: "x").mustIncludeItemIds == [id])
        #expect(IntentMerge.merge(ParsedIntent(occasion: .office), previous: nil, message: "x").mustIncludeItemIds.isEmpty)
    }
    @Test("changing occasion drops the old occasion's overrides") func occasionChange() {
        var prev = festival; prev.dressCode = .festive; prev.formalityMin = 3; prev.formalityMax = 4
        let out = IntentMerge.merge(ParsedIntent(occasion: .gym), previous: prev, message: "gym instead")
        #expect(out.occasion == .gym && out.dressCode == nil && out.formalityMax == nil && out.timeOfDay == .evening)
    }
    @Test("flags union and avoid accumulate across turns") func accumulate() {
        var prev = festival; prev.flags = [.fireworks]; prev.avoid = [.colour(.black)]
        let out = IntentMerge.merge(ParsedIntent(flags: [.photoHeavy], avoid: ["jeans"]), previous: prev, message: "x")
        #expect(out.flags == [.fireworks, .photoHeavy] && out.avoid == [.colour(.black), .subcategory(.jeans)])
    }
}
