import Foundation
import Testing
@testable import StyleEngine

@Suite("S4 fix round 1: engine") struct EngineFixRound1Tests {
    @Test("S4-F01 no footwear: outfits still built, footwear is a soft hint") func noShoes() {
        let r = run(.init(occasion: .casualDay), Array(basics()[0...1]))
        #expect(r.outfits.count == 1 && r.softMissing == [.footwear] && r.missing.isEmpty)
        #expect(r.outfits[0].slots[.footwear] == nil && r.outfits[0].slots[.top] != nil && r.outfits[0].slots[.bottom] != nil)
        #expect(run(.init(occasion: .casualDay), basics()).softMissing.isEmpty)
        // top and bottom stay required
        let nobottom = run(.init(occasion: .casualDay), [basics()[0], basics()[2]])
        #expect(nobottom.outfits.isEmpty && nobottom.missing.contains(.bottom))
    }
    @Test("S4-F02 open-toe only counts as no footwear in cold") func coldSandalsOnly() {
        let items = Array(basics()[0...1]) + [mk("Sandals", .footwear, .sandals, [.brown])]
        #expect(run(.init(occasion: .casualDay, weatherFeel: .hot), items).softMissing.isEmpty)
    }
    @Test("S4-F03 twin tees: top 3 never differs only by the twin") func twins() {
        let teeA = mk("Tee A", .top, .tshirt, [.white]), teeB = mk("Tee B", .top, .tshirt, [.white])
        let all = [teeA, teeB, mk("Jeans", .bottom, .jeans, [.black]), mk("Sneakers", .footwear, .sneakers, [.white]),
                   mk("Chinos", .bottom, .chinos, [.navy])]
        let r = run(.init(occasion: .casualDay), all, count: 6)
        let looks = r.outfits.map { OutfitEngine.look(of: $0, items: all) }
        #expect(r.outfits.count >= 2 && Set(looks).count == looks.count)
    }
    @Test("S4-F04 excluded looks are skipped by candidates, not by swaps") func excludeLooks() {
        let teeA = mk("Tee A", .top, .tshirt, [.white]), teeB = mk("Tee B", .top, .tshirt, [.white])
        let all = [teeA, teeB, mk("Jeans", .bottom, .jeans, [.black]), mk("Sneakers", .footwear, .sneakers, [.white])]
        let first = run(.init(occasion: .casualDay), all).outfits
        #expect(first.count == 1)
        let looks = Set(first.map { OutfitEngine.look(of: $0, items: all) })
        let c = EngineContext(today: testToday, excludeOutfits: Set(first.map(\.key)), seed: 7, excludeLooks: looks)
        #expect(OutfitEngine.generate(intent: .init(occasion: .casualDay), items: all, context: c).outfits.isEmpty)
        let alts = OutfitEngine.alternatives(for: .top, in: first[0], intent: .init(occasion: .casualDay), items: all, context: c)
        #expect(alts.count == 1)    // the twin is still offered as a swap
    }
    @Test("S4-F05 cold: hoodie + jeans + sneakers tagged summer still make an outfit") func coldHoodie() {
        let hoodie = mk("Navy hoodie", .top, .hoodie, [.navy], dc: [.casual], f: 2, warmth: 2, seasons: [.winter])
        let jeans = mk("Jeans", .bottom, .jeans, [.grey], dc: [.casual], f: 2, fabric: .denim, seasons: [.summer])
        let shoes = mk("Sneakers", .footwear, .sneakers, [.white], dc: [.casual], f: 2, seasons: [.summer])
        let r = run(.init(occasion: .casualDay, weatherFeel: .cold), [hoodie, jeans, shoes])
        #expect(!r.outfits.isEmpty && r.outfits.allSatisfy { $0.slots.values.contains(hoodie.id) })
        // a hoodie the AI tagged warmth 1 still counts as a warm layer
        let flat = mk("Navy hoodie", .top, .hoodie, [.navy], dc: [.casual], f: 2, warmth: 1, seasons: [.summer])
        #expect(!run(.init(occasion: .casualDay, weatherFeel: .cold), [flat, jeans, shoes]).outfits.isEmpty)
    }
    @Test("S4-F06 cold rejects shorts and open-toe shoes only") func coldHot() {
        let shorts = mk("Shorts", .bottom, .shorts, [.beige], dc: [.casual, .smartCasual])
        let sandals = mk("Sandals", .footwear, .sandals, [.brown], dc: [.casual, .smartCasual])
        let r = run(.init(occasion: .casualDay, weatherFeel: .cold), basics() + [shorts, sandals])
        #expect(r.rejected[shorts.id] == .wrongSeason && r.rejected[sandals.id] == .wrongSeason)
        #expect(r.rejected[basics()[1].id] == nil)
    }
}

@Suite("S4 fix round 1: twins must not crowd out other looks") struct TwinCrowdingTests {
    @Test("S4-F11 three twin jeans and three twin chinos: both looks are candidates") func crowding() {
        var all = [mk("Tee", .top, .tshirt, [.white]), mk("Sneakers", .footwear, .sneakers, [.white])]
        for n in 0..<3 { all += [mk("Jeans \(n)", .bottom, .jeans, [.black]), mk("Chinos \(n)", .bottom, .chinos, [.navy])] }
        let looks = Set(OutfitEngine.candidates(intent: .init(occasion: .casualDay), items: all, context: ctx())
            .map { OutfitEngine.look(of: $0, items: all) })
        #expect(looks.count == 2)
    }
}
