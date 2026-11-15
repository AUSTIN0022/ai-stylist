import Foundation
import Testing
@testable import StyleEngine

@Suite("S4 session, another option, swap") struct SessionTests {
    let intent = OccasionIntent.diwali

    @Test("S4-U16 shown keys accumulate") func u16() throws {
        let f = try loadFixture()
        var s = StylistSession()
        s.start(intent: intent, items: f.items, today: testToday)
        let first = s.outfits.map(\.candidate.key)
        #expect(first.count == 3)
        let replaced = s.another(intent: intent, items: f.items, today: testToday)
        #expect(replaced.map(\.candidate.key) == first)
        let second = s.outfits.map(\.candidate.key)
        #expect(second.count == 3 && Set(first).isDisjoint(with: Set(second)))
        #expect(s.shown == Set(first + second))
        #expect(Set(s.outfits.map(\.id)).isDisjoint(with: Set(replaced.map(\.id))))
    }
    @Test("S4-U17 exhausted keeps the missing slots, not an empty screen") func u17() throws {
        let b = basics()
        var s = StylistSession()
        s.start(intent: .init(occasion: .casualDay), items: b, today: testToday)
        #expect(s.outfits.count == 1 && s.state == .showing)
        let replaced = s.another(intent: .init(occasion: .casualDay), items: b, today: testToday)
        #expect(replaced.isEmpty && s.outfits.count == 1)           // the last outfit stays visible
        guard case .exhausted = s.state else { Issue.record("expected exhausted"); return }

        let f = try loadFixture("wardrobe_nofootwear")
        var n = StylistSession()
        n.start(intent: intent, items: f.items, today: testToday)
        #expect(!n.outfits.isEmpty && n.state == .showing && n.softMissing == [.footwear])   // fix round 1: shoes are soft
    }
    @Test("S4-U18 alternatives pass the hard checks") func u18() throws {
        let f = try loadFixture()
        var s = StylistSession(); s.start(intent: intent, items: f.items, today: testToday)
        let r = OutfitEngine.generate(intent: intent, items: f.items, context: EngineContext(today: testToday))
        for o in s.outfits {
            for slot in o.candidate.slots.keys {
                for alt in s.alternatives(for: o.id, slot: slot, intent: intent, items: f.items, today: testToday) {
                    let id = alt.slots[slot]!
                    #expect(r.kept.contains(id) && r.rejected[id] == nil)
                    #expect(!s.shown.contains(alt.key))
                }
            }
        }
    }
    @Test("S4-U19 alternatives are for that slot only") func u19() throws {
        let f = try loadFixture()
        var s = StylistSession(); s.start(intent: intent, items: f.items, today: testToday)
        let o = s.outfits[0]
        let alts = s.alternatives(for: o.id, slot: .footwear, intent: intent, items: f.items, today: testToday)
        #expect(!alts.isEmpty)
        for a in alts {
            #expect(f.items.first { $0.id == a.slots[.footwear] }?.cat == .footwear)
            #expect(a.slots[.footwear] != o.candidate.slots[.footwear])
        }
    }
    @Test("S4-U20 swap replaces one item") func u20() throws {
        let f = try loadFixture()
        var s = StylistSession(); s.start(intent: intent, items: f.items, today: testToday)
        let o = s.outfits[0]
        let alt = try #require(s.alternatives(for: o.id, slot: .footwear, intent: intent, items: f.items, today: testToday).first)
        let new = alt.slots[.footwear]!
        s.swap(o.id, slot: .footwear, to: new)
        let after = s.outfits[0]
        #expect(after.id == o.id && after.candidate.slots[.footwear] == new)
        for (slot, id) in o.candidate.slots where slot != .footwear { #expect(after.candidate.slots[slot] == id) }
        #expect(s.shown.contains(after.candidate.key))      // a swapped outfit is never offered again
    }
}

@Suite("S4 fix round 1: session") struct SessionFixRound1Tests {
    @Test("S4-F07 Another option never shows a look already shown") func anotherLooks() {
        var all: [EngineItem] = []
        for n in 0..<2 { all += [mk("Tee \(n)", .top, .tshirt, [.white]), mk("Jeans \(n)", .bottom, .jeans, [.black])] }
        all += [mk("Shirt", .top, .shirt, [.cream]), mk("Chinos", .bottom, .chinos, [.navy]), mk("Sneakers", .footwear, .sneakers, [.white])]
        let intent = OccasionIntent(occasion: .casualDay)
        var s = StylistSession(); s.start(intent: intent, items: all, today: testToday)
        var seen = Set(s.outfits.map { OutfitEngine.look(of: $0.candidate, items: all) })
        #expect(seen.count == s.outfits.count)
        var rounds = 0
        for _ in 0..<3 {
            if s.another(intent: intent, items: all, today: testToday).isEmpty { break }     // exhausted: old outfits stay
            rounds += 1
            let looks = s.outfits.map { OutfitEngine.look(of: $0.candidate, items: all) }
            #expect(Set(looks).count == looks.count && seen.isDisjoint(with: looks))
            seen.formUnion(looks)
        }
        #expect(rounds >= 1)
    }
}
