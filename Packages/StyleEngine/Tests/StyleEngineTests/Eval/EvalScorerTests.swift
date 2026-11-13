import Testing
import Foundation
@testable import StyleEngine

private func one(_ exp: EvalTags, _ got: EvalTags, field: String) -> EvalScorer.FieldScore {
    EvalScorer.score([.init(id: "x", expected: exp, got: got)]).fields[field] ?? .init(right: 0, scored: 0)
}

@Suite("S0 eval scorer")
struct EvalScorerTests {
    @Test("S0-U01 single correct") func u01() {
        let s = one(["collar": "mandarin"], ["collar": "mandarin"], field: "collar")
        #expect(s.right == 1 && s.scored == 1)
    }
    @Test("S0-U02 single wrong") func u02() {
        let s = one(["collar": "mandarin"], ["collar": "spread"], field: "collar")
        #expect(s.right == 0 && s.scored == 1)
    }
    @Test("S0-U03 list, first expected present") func u03() {
        let s = one(["dressCodes": ["smartCasual", "festive"]], ["dressCodes": ["casual", "smartCasual"]], field: "dressCodes")
        #expect(s.right == 1)
    }
    @Test("S0-U04 list, first expected absent") func u04() {
        let s = one(["dressCodes": ["smartCasual", "festive"]], ["dressCodes": ["festive"]], field: "dressCodes")
        #expect(s.right == 0 && s.scored == 1)
    }
    @Test("S0-U05 field missing from expected is not counted") func u05() {
        let r = EvalScorer.score([.init(id: "x", expected: ["category": "top"], got: ["category": "top", "fabric": "linen"])])
        #expect(r.fields["fabric"] == nil)
        #expect(r.fields["category"]?.scored == 1)
    }
    @Test("S0-U06 field missing from answer scores 0") func u06() {
        let s = one(["fabric": "linen"], [:], field: "fabric")
        #expect(s.right == 0 && s.scored == 1)
    }
    @Test("S0-U07 accuracy maths") func u07() {
        let items = (0..<30).map { i in
            EvalScorer.Item(id: "i\(i)", expected: ["category": "top"], got: ["category": i < 27 ? "top" : "bottom"])
        }
        #expect(EvalScorer.score(items).accuracy("category") == 90.0)
    }
    @Test("S0-U08 zero scored is n/a") func u08() {
        let r = EvalScorer.score([.init(id: "x", expected: [:], got: ["fabric": "linen"])])
        #expect(r.accuracy("fabric") == nil)
        #expect(r.accuracyText("fabric") == "n/a")
    }
    @Test("S0-U09 timing summary") func u09() {
        let t = TimingSummary([4, 6, 8, 30])
        #expect(t?.median == 7 && t?.worst == 30)
        #expect(TimingSummary([]) == nil)
    }
    @Test("S0-U10 expected decodes and validates enums") func u10() throws {
        let allowed = ["collar": Set(["mandarin", "spread"]), "colors": Set(["rust", "navy"])]
        let ok = Data(#"{"a":{"collar":"mandarin","colors":["rust","navy"]}}"#.utf8)
        let m = try ExpectedFile.decode(ok, allowed: allowed)
        #expect(m["a"]?["collar"] == "mandarin")
        #expect(m["a"]?["colors"] == ["rust", "navy"])

        let bad = Data(#"{"a":{"collar":"mandarin"},"b":{"collar":"mandrin"}}"#.utf8)
        do {
            _ = try ExpectedFile.decode(bad, allowed: allowed)
            Issue.record("should throw")
        } catch let e as ExpectedFile.DecodeError {
            #expect(e == .invalidValue(id: "b", field: "collar", value: "mandrin"))
            #expect(e.description.contains("b") && e.description.contains("collar") && e.description.contains("mandrin"))
        }
        let unk = Data(#"{"a":{"colour":"rust"}}"#.utf8)
        #expect(throws: ExpectedFile.DecodeError.self) { try ExpectedFile.decode(unk, allowed: allowed) }
        let shape = Data(#"{"a":{"collar":3}}"#.utf8)
        #expect(throws: ExpectedFile.DecodeError.self) { try ExpectedFile.decode(shape, allowed: allowed) }
    }
    @Test("S0-U11 photo and expected ids match") func u11() {
        let m = IDMatch(photoIDs: ["a", "b", "c"], expectedIDs: ["b", "c", "d"])
        #expect(m.photosWithoutExpected == ["a"])
        #expect(m.expectedWithoutPhoto == ["d"])
        #expect(!m.isComplete)
        #expect(IDMatch(photoIDs: ["a"], expectedIDs: ["a"]).isComplete)
    }
    @Test("S0-U12 pass marks") func u12() {
        // Fabric target raised to 75% on 14 Nov (TEST_PLAN §5): 70 fails, 75 passes.
        let acc: [String: Double?] = ["category": 96, "subcategory": 80, "fabric": 70, "fit": 75, "collar": nil]
        let r = PassMarks.check(acc)
        #expect(r.passed == ["category", "fit"])
        #expect(r.failed == ["fabric", "subcategory"])
        #expect(r.notScored == ["collar"])
    }
}
