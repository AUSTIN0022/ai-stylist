import Foundation
import Testing
@testable import StyleEngine

@Suite("S3 filter stage") struct EngineFilterTests {
    func ids(_ r: EngineResult, _ reason: RejectReason) -> Set<UUID> { Set(r.rejected.filter { $0.value == reason }.keys) }

    @Test("S3-U06 notReady") func u06() {
        let empty = EngineItem(name: "Empty", tags: ItemTags(), colors: [.black])
        let busy = mk("Busy", .top, .shirt, [.blue])
        let b = EngineItem(id: busy.id, name: "Busy", tags: busy.tags, colors: [.blue], isReady: false)
        let r = run(.init(occasion: .casualDay), basics() + [empty, b])
        #expect(r.rejected[empty.id] == .notReady)
        #expect(r.rejected[b.id] == .notReady)
    }
    @Test("S3-U07 avoided colour") func u07() {
        let blackTee = mk("Black tee", .top, .tshirt, [.black], dc: [.casual, .smartCasual])
        let b = basics()
        let r = run(.init(occasion: .casualDay, avoid: [.colour(.black)]), b + [blackTee])
        #expect(r.rejected[blackTee.id] == .avoided)
        #expect(r.rejected[b[1].id] == .avoided)   // the black chinos
        #expect(r.rejected[b[0].id] == nil)
    }
    @Test("S3-U08 avoided subcategory") func u08() {
        let jeans = mk("Jeans", .bottom, .jeans, [.navy], dc: [.casual, .smartCasual], f: 2, fabric: .denim)
        let b = basics()
        let r = run(.init(occasion: .casualDay, avoid: [.subcategory(.jeans)]), b + [jeans])
        #expect(r.rejected[jeans.id] == .avoided)
        #expect(r.rejected[b[1].id] == nil)  // chinos kept
    }
    @Test("S3-U09 wrongDressCode") func u09() {
        let tee = mk("Graphic tee", .top, .tshirt, [.black], dc: [.casual], f: 4, pattern: .graphic, statement: .statement)
        let r = run(.init(occasion: .interview), basics() + [tee])
        #expect(r.rejected[tee.id] == .wrongDressCode)
    }
    @Test("S3-U10 formality range plus or minus one") func u10() {
        let ok = mk("F3", .top, .shirt, [.lightBlue], dc: [.businessCasual], f: 3)
        let bad = mk("F2", .top, .shirt, [.lightBlue], dc: [.businessCasual], f: 2)
        let r = run(.init(occasion: .interview), basics() + [ok, bad])
        #expect(r.rejected[ok.id] == nil)
        #expect(r.rejected[bad.id] == .formalityOutOfRange)
    }
    @Test("S3-U11 tooWarm in heat") func u11() {
        let knit = mk("Chunky knit", .top, .sweater, [.brown], dc: [.casual], f: 2, fabric: .knit, warmth: 3)
        let r = run(.init(occasion: .casualDay, weatherFeel: .hot), basics() + [knit])
        #expect(r.rejected[knit.id] == .tooWarm)
    }
    @Test("S3-U12 openToeBlocked with fireworks") func u12() {
        let sandals = mk("Sandals", .footwear, .sandals, [.brown], dc: [.smartCasual, .festive])
        let slides = mk("Slides", .footwear, .slides, [.black], dc: [.smartCasual, .festive])
        let sneakers = mk("Sneakers", .footwear, .sneakers, [.cream], dc: [.smartCasual, .festive])
        let r = run(.init(occasion: .festival, flags: [.fireworks]), basics() + [sandals, slides, sneakers])
        #expect(r.rejected[sandals.id] == .openToeBlocked)
        #expect(r.rejected[slides.id] == .openToeBlocked)
        #expect(r.rejected[sneakers.id] == nil)
        let r2 = run(.init(occasion: .festival), basics() + [sandals, slides, sneakers])
        #expect(r2.rejected[sandals.id] == nil)
    }
    @Test("S3-U13 ruleBlocked by the occasion rule") func u13() {
        let tee = mk("Graphic tee", .top, .tshirt, [.black], dc: [.smartCasual], f: 3, pattern: .graphic, statement: .statement)
        let slides = mk("Slides", .footwear, .slides, [.black], dc: [.smartCasual], f: 3)
        let r = run(.init(occasion: .office), basics() + [tee, slides])
        #expect(r.rejected[tee.id] == .ruleBlocked)
        #expect(r.rejected[slides.id] == .ruleBlocked)
    }
    @Test("flag rules: religiousSite and lotsOfWalking") func flags() {
        let shorts = mk("Shorts", .bottom, .shorts, [.beige], dc: [.casual, .smartCasual, .festive], f: 3)
        let tank = mk("Tank", .top, .tshirt, [.white], dc: [.casual, .smartCasual, .festive], f: 3)
        var t = tank.tags; t.sleeve = .sleeveless
        let sleeveless = EngineItem(id: tank.id, name: "Tank", tags: t, colors: [.white])
        let r = run(.init(occasion: .puja, flags: [.religiousSite]), basics() + [shorts, sleeveless])
        #expect(r.rejected[shorts.id] == .ruleBlocked)
        #expect(r.rejected[sleeveless.id] == .ruleBlocked)
        let formal = mk("Oxfords", .footwear, .formalShoes, [.black], dc: [.casual], f: 2)
        let slides = mk("Slides", .footwear, .slides, [.black], dc: [.casual], f: 2)
        let r2 = run(.init(occasion: .casualDay, flags: [.lotsOfWalking]), basics() + [formal, slides])
        #expect(r2.rejected[formal.id] == .ruleBlocked)
        #expect(r2.rejected[slides.id] != nil)
    }
    @Test("interview wants plain or subtle pattern and closed toe") func interviewRules() {
        let check = mk("Check shirt", .top, .shirt, [.rust], dc: [.businessCasual], f: 4, pattern: .check, statement: .medium)
        let sandals = mk("Sandals", .footwear, .sandals, [.brown], dc: [.businessCasual], f: 4)
        let r = run(.init(occasion: .interview), basics() + [check, sandals])
        #expect(r.rejected[check.id] == .ruleBlocked)
        #expect(r.rejected[sandals.id] == .openToeBlocked)
    }
    @Test("S3-U14 wornRecently is soft") func u14() {
        let yesterday = testToday.addingTimeInterval(-86_400)
        let worn = mk("Worn top", .top, .shirt, [.blue], worn: yesterday)
        let other = mk("Other top", .top, .shirt, [.white])
        let bottom = mk("B", .bottom, .chinos, [.black]), shoes = mk("S", .footwear, .sneakers, [.white])
        let r = run(.init(occasion: .casualDay), [worn, other, bottom, shoes])
        #expect(r.rejected[worn.id] == .wornRecently)
        let r2 = run(.init(occasion: .casualDay), [worn, bottom, shoes])
        #expect(r2.rejected[worn.id] == nil)
        #expect(!r2.outfits.isEmpty)
        let three = mk("Three days", .top, .shirt, [.blue], worn: testToday.addingTimeInterval(-3 * 86_400))
        #expect(run(.init(occasion: .casualDay), [three, other, bottom, shoes]).rejected[three.id] == nil)
    }
    @Test("S3-U15 pinned skips filters") func u15() {
        let tee = mk("Graphic tee", .top, .tshirt, [.black], dc: [.casual], f: 1, pattern: .graphic, statement: .statement)
        let r = run(.init(occasion: .interview, mustIncludeItemIds: [tee.id]), basics() + [tee])
        #expect(r.rejected[tee.id] == nil)
        #expect(r.kept.contains(tee.id))
    }
    @Test("wrongSeason: winter-only items in heat, shorts in cold") func season() {
        let cords = mk("Cords", .bottom, .trousers, [.olive], dc: [.casual, .smartCasual], f: 3, fabric: .corduroy, warmth: 2, seasons: [.winter])
        let linen = mk("Linen", .bottom, .shorts, [.brown], dc: [.casual, .smartCasual], f: 3, fabric: .linen, seasons: [.summer])
        let hot = run(.init(occasion: .casualDay, weatherFeel: .hot), basics() + [cords, linen])
        #expect(hot.rejected[cords.id] == .wrongSeason)
        let cold = run(.init(occasion: .casualDay, weatherFeel: .cold), basics() + [cords, linen])
        #expect(cold.rejected[linen.id] == .wrongSeason)
        #expect(cold.rejected[cords.id] == nil)
    }
    @Test("intent dressCode and formality override the table") func overrides() {
        let party = mk("Party top", .top, .shirt, [.black], dc: [.party], f: 5)
        let base = run(.init(occasion: .office), basics() + [party])
        #expect(base.rejected[party.id] == .wrongDressCode)
        let over = run(.init(occasion: .office, dressCode: .party, formalityMin: 5, formalityMax: 5), basics() + [party])
        #expect(over.rejected[party.id] == nil)
    }
    @Test("S3-U38 every item is kept or rejected with a reason") func u38() throws {
        let f = try loadFixture()
        for o in Occasion.allCases {
            let r = run(.init(occasion: o), f.items)
            #expect(r.kept.count + r.rejected.count == f.items.count, "\(o)")
            #expect(Set(r.kept).isDisjoint(with: Set(r.rejected.keys)))
        }
    }
}
