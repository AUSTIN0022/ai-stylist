import Foundation
import Testing
@testable import StyleEngine

// S6-U01..U05: the duplicate-check decision, with made-up distances (the real feature print needs Vision).

@Suite("S6 duplicate check") struct DuplicateCheckTests {
    let a = UUID(), b = UUID(), c = UUID()
    func cand(_ id: UUID, _ sub: Subcategory?) -> DuplicateCandidate { DuplicateCandidate(id: id, subcategory: sub) }

    @Test("S6-U01 under the threshold is a possible duplicate") func match() {
        let m = DuplicateCheck.match(subcategory: .shirt, among: [cand(a, .shirt)], distance: { _ in 0.2 })
        #expect(m?.id == a)
    }
    @Test("S6-U02 over the threshold: no prompt") func noMatch() {
        #expect(DuplicateCheck.match(subcategory: .shirt, among: [cand(a, .shirt)], distance: { _ in DuplicateCheck.threshold + 0.3 }) == nil)
    }
    @Test("S6-U03 same subcategory only") func subcategory() {
        #expect(DuplicateCheck.match(subcategory: .shirt, among: [cand(a, .chinos)], distance: { _ in 0.01 }) == nil)
        // Unknown on either side (tagging off or not finished): the print decides.
        #expect(DuplicateCheck.match(subcategory: nil, among: [cand(a, .chinos)], distance: { _ in 0.01 })?.id == a)
        #expect(DuplicateCheck.match(subcategory: .shirt, among: [cand(a, nil)], distance: { _ in 0.01 })?.id == a)
    }
    @Test("S6-U04 the nearer of two is offered") func closest() {
        let d: [UUID: Double] = [a: 0.30, b: 0.10, c: 0.35]
        #expect(DuplicateCheck.match(subcategory: .shirt, among: [cand(a, .shirt), cand(b, .shirt), cand(c, .shirt)], distance: { d[$0] })?.id == b)
    }
    @Test("S6-U05 items without a print are skipped") func missingPrint() {
        let d: [UUID: Double] = [b: 0.2]
        let m = DuplicateCheck.match(subcategory: .shirt, among: [cand(a, .shirt), cand(b, .shirt)], distance: { d[$0] })
        #expect(m?.id == b)
        #expect(DuplicateCheck.match(subcategory: .shirt, among: [cand(a, .shirt)], distance: { _ in nil }) == nil)
        #expect(DuplicateCheck.match(subcategory: .shirt, among: [], distance: { _ in 0 }) == nil)
    }
}
