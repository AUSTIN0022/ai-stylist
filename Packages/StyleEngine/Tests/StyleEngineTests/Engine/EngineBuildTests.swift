import Foundation
import Testing
@testable import StyleEngine

@Suite("S3 formulas, sets, hard checks") struct EngineBuildTests {
    func cands(_ intent: OccasionIntent, _ items: [EngineItem], _ c: EngineContext? = nil) -> [OutfitCandidate] {
        OutfitEngine.candidates(intent: intent, items: items, context: c ?? ctx())
    }

    // MARK: formulas
    @Test("S3-U16 top + bottom + footwear") func u16() {
        let r = run(.init(occasion: .casualDay), basics())
        #expect(r.outfits.count == 1)
        #expect(Set(r.outfits[0].slots.keys) == [.top, .bottom, .footwear])
    }
    @Test("S3-U17 outerwear only when cold") func u17() {
        let jacket = mk("Jacket", .outerwear, .jacket, [.charcoal], f: 3, warmth: 2)
        let all = basics() + [jacket]
        let mild = run(.init(occasion: .casualDay, weatherFeel: .mild), all, count: 10)
        #expect(!mild.outfits.isEmpty)
        #expect(mild.outfits.allSatisfy { $0.slots[.outerwear] == nil })
        let cold = run(.init(occasion: .casualDay, weatherFeel: .cold), all, count: 10)
        #expect(!cold.outfits.isEmpty)
        #expect(cold.outfits.allSatisfy { $0.slots[.outerwear] == jacket.id })   // light top needs the jacket
        let rainy = cands(.init(occasion: .casualDay, weatherFeel: .rainy), all)
        #expect(rainy.contains { $0.slots[.outerwear] != nil } && rainy.contains { $0.slots[.outerwear] == nil })
    }
    @Test("S3-U18 layered formula") func u18() {
        let tee = mk("Tee", .top, .tshirt, [.white], dc: [.casual, .smartCasual], f: 2, fabric: .jersey, fit: .slim)
        let knit = mk("Knit", .top, .sweater, [.navy], dc: [.casual, .smartCasual], f: 3, fabric: .knit, warmth: 2)
        let all = [tee, knit] + Array(basics()[1...])
        let cs = cands(.init(occasion: .casualDay, weatherFeel: .mild), all)
        #expect(cs.contains { $0.slots[.baseLayer] == tee.id && $0.slots[.top] == knit.id })
        // no overlayer survives -> never a baseLayer slot
        let none = cands(.init(occasion: .casualDay), [tee] + Array(basics()[1...]))
        #expect(none.allSatisfy { $0.slots[.baseLayer] == nil })
    }
    @Test("S3-U19 one-piece") func u19() {
        let dress = mk("Dress", .onePiece, .dress, [.maroon], dc: [.smartCasual, .party], f: 3)
        let shoes = mk("Shoes", .footwear, .sneakers, [.white], dc: [.smartCasual, .party])
        let r = run(.init(occasion: .date), [dress, shoes])
        #expect(r.outfits.count == 1)
        #expect(Set(r.outfits[0].slots.keys) == [.onePiece, .footwear])
    }
    @Test("S3-U20 nothing feasible reports the missing slot") func u20() {
        let r = run(.init(occasion: .casualDay), [basics()[0], basics()[2]])   // fix round 1: shoes are soft, a bottom is not
        #expect(r.outfits.isEmpty)
        #expect(r.missing.contains(.bottom))
        #expect(!r.missing.contains(.top))
    }
    @Test("S3-U21 accessories: at most two, formality within one") func u21() {
        let acc = [mk("Watch", .accessory, .watch, [.silver], f: 3), mk("Chain", .accessory, .chain, [.gold], f: 3),
                   mk("Belt", .accessory, .belt, [.black], f: 3), mk("Cap", .accessory, .cap, [.black], dc: [.casual, .smartCasual], f: 1)]
        let all = basics() + acc
        let r = run(.init(occasion: .casualDay), all, count: 5)
        #expect(!r.outfits.isEmpty)
        for o in r.outfits {
            let accs = items(of: o, in: all).filter { $0.cat == .accessory }
            let c = core(of: o, in: all)
            let mean = Double(c.map { $0.tags.formality! }.reduce(0, +)) / Double(c.count)
            #expect(accs.count == 2)
            #expect(accs.allSatisfy { abs(Double($0.tags.formality!) - mean) <= 1 })
            #expect(!accs.contains { $0.name == "Cap" })
            #expect(Set(o.slots.keys).isSuperset(of: [.accessory1, .accessory2]))
        }
    }

    // MARK: sets
    func setWardrobe() -> (all: [EngineItem], kurta: EngineItem, pyjama: EngineItem) {
        let g = UUID()
        let kurta = mk("Kurta", .top, .kurta, [.mustard], dc: [.festive, .smartCasual], f: 4, origin: .indian)
        let k = EngineItem(id: kurta.id, name: "Kurta", tags: { var t = kurta.tags; t.setRole = SetRole.kurta; return t }(), colors: [.mustard], setGroupId: g)
        let py = mk("Pyjama", .bottom, .pyjama, [.cream], dc: [.festive, .smartCasual], f: 4, origin: .indian)
        let p = EngineItem(id: py.id, name: "Pyjama", tags: { var t = py.tags; t.setRole = SetRole.kurtaBottom; return t }(), colors: [.cream], setGroupId: g)
        let others = [mk("Shirt", .top, .shirt, [.rust], dc: [.festive, .smartCasual], f: 3),
                      mk("Jeans", .bottom, .jeans, [.navy], dc: [.casual, .smartCasual, .festive], f: 3, fabric: .denim),
                      mk("Chinos", .bottom, .chinos, [.black], dc: [.smartCasual, .festive], f: 3),
                      mk("Juttis", .footwear, .juttis, [.tan], dc: [.festive, .smartCasual], f: 4, origin: .indian),
                      mk("Sneakers", .footwear, .sneakers, [.cream], dc: [.festive, .smartCasual], f: 3)]
        return ([k, p] + others, k, p)
    }
    @Test("S3-U22 set is one unit") func u22() {
        let (all, k, p) = setWardrobe()
        let cs = cands(.init(occasion: .festival), all)
        #expect(cs.contains { $0.slots.values.contains(k.id) })
        for o in cs { #expect(o.slots.values.contains(k.id) == o.slots.values.contains(p.id)) }
        let kurtaOutfit = cs.first { $0.slots.values.contains(k.id) }!
        #expect(kurtaOutfit.slots[.setTop] == k.id && kurtaOutfit.slots[.setBottom] == p.id)
        #expect(kurtaOutfit.slots[.footwear] != nil)
    }
    @Test("S3-U23 set item never used alone") func u23() {
        let (all, k, _) = setWardrobe()
        for o in cands(.init(occasion: .festival), all) where o.slots.values.contains(k.id) {
            let names = Set(items(of: o, in: all).map(\.name))
            #expect(names.isDisjoint(with: ["Jeans", "Chinos", "Shirt"]))
            #expect(o.slots[.top] == nil && o.slots[.bottom] == nil)
        }
    }
    @Test("S3-U24 pinned set item brings its set") func u24() {
        let (all, k, p) = setWardrobe()
        let r = run(.init(occasion: .festival, mustIncludeItemIds: [k.id]), all, count: 5)
        #expect(!r.outfits.isEmpty)
        #expect(r.outfits.allSatisfy { $0.slots.values.contains(k.id) && $0.slots.values.contains(p.id) })
        let r2 = run(.init(occasion: .festival, mustIncludeItemIds: [p.id]), all, count: 5)
        #expect(!r2.outfits.isEmpty && r2.outfits.allSatisfy { $0.slots.values.contains(k.id) })
    }
    @Test("a set with one rejected member is not offered") func brokenSet() {
        let (all, k, p) = setWardrobe()
        let r = run(.init(occasion: .festival, avoid: [.colour(.cream)]), all, count: 10)
        #expect(r.rejected[p.id] == .avoided)
        #expect(r.outfits.allSatisfy { !$0.slots.values.contains(k.id) })
    }

    // MARK: hard checks
    @Test("S3-U25 one pattern only") func u25() {
        let check = mk("Check shirt", .top, .shirt, [.rust, .cream], dc: [.casual, .smartCasual], f: 2, pattern: .check, statement: .medium)
        let rugby = mk("Rugby", .top, .polo, [.navy, .green], dc: [.casual], f: 2, pattern: .stripe, statement: .medium)
        let gfx = mk("Graphic tee", .top, .tshirt, [.black], dc: [.casual], f: 1, pattern: .graphic, statement: .statement)
        let tee = mk("Tee", .top, .tshirt, [.white], dc: [.casual], f: 2, fit: .slim)
        let jeans = mk("Jeans", .bottom, .jeans, [.black], dc: [.casual, .smartCasual], f: 2, fabric: .denim)
        let shoes = mk("Shoes", .footwear, .sneakers, [.white], dc: [.casual], f: 2)
        let all = [check, rugby, gfx, tee, jeans, shoes]
        for w in [WeatherFeel.mild, .unknown] {
            let cs = cands(.init(occasion: .casualDay, weatherFeel: w), all)
            #expect(!cs.isEmpty)
            for o in cs { #expect(core(of: o, in: all).filter(\.isNonSolidOrStatement).count <= 1) }
        }
        #expect(cands(.init(occasion: .casualDay), all).contains { $0.slots.values.contains(check.id) })
    }
    @Test("S3-U25 on the fixture: check shirt never with rugby or graphic tees") func u25fixture() throws {
        let f = try loadFixture()
        for o in Occasion.allCases { for w in [WeatherFeel.mild, .cold, .hot] {
            for c in cands(.init(occasion: o, weatherFeel: w), f.items) {
                #expect(core(of: c, in: f.items).filter(\.isNonSolidOrStatement).count <= 1, "\(o) \(w)")
            }
        } }
    }
    @Test("S3-U26 formality spread at most 2") func u26() throws {
        let f = try loadFixture()
        for o in Occasion.allCases { for w in [WeatherFeel.mild, .cold] {
            for c in cands(.init(occasion: o, weatherFeel: w), f.items) {
                let fs = core(of: c, in: f.items).map { $0.tags.formality! }
                #expect(fs.max()! - fs.min()! <= 2, "\(o) \(w)")
            }
        } }
        // small case: formality 5 top with formality 2 shoes can never combine
        let top = mk("Top", .top, .shirt, [.white], dc: [.casual], f: 5)
        let shoes = mk("Shoes", .footwear, .sneakers, [.white], dc: [.casual], f: 2)
        let b = mk("B", .bottom, .chinos, [.black], dc: [.casual], f: 4)
        #expect(cands(.init(occasion: .casualDay, formalityMin: 1, formalityMax: 5), [top, shoes, b]).isEmpty)
    }
    @Test("S3-U27 same colour top and bottom") func u27() {
        let rustTop = mk("Rust top", .top, .shirt, [.rust], f: 3)
        let rustBottom = mk("Rust bottom", .bottom, .chinos, [.rust], f: 3)
        let blackBottom = mk("Black bottom", .bottom, .chinos, [.black], f: 3)
        let shoes = mk("Shoes", .footwear, .sneakers, [.cream], f: 3)
        let all = [rustTop, rustBottom, blackBottom, shoes]
        let cs = cands(.init(occasion: .casualDay), all)
        #expect(!cs.isEmpty)
        #expect(cs.allSatisfy { !($0.slots.values.contains(rustTop.id) && $0.slots.values.contains(rustBottom.id)) })
        // navy knit with indigo jeans: same blue family
        let knit = mk("Navy knit", .top, .sweater, [.navy], dc: [.casual, .smartCasual], f: 3, fabric: .knit, warmth: 2)
        let indigo = mk("Indigo jeans", .bottom, .jeans, [.navy], dc: [.casual, .smartCasual], f: 3, fabric: .denim)
        let blue = mk("Blue chinos", .bottom, .chinos, [.blue], dc: [.casual, .smartCasual], f: 3)
        let ok = mk("Beige chinos", .bottom, .chinos, [.beige], dc: [.casual, .smartCasual], f: 3)
        let all2 = [knit, indigo, blue, ok, shoes]
        let cs2 = cands(.init(occasion: .casualDay), all2)
        #expect(cs2.contains { $0.slots.values.contains(knit.id) })
        #expect(cs2.allSatisfy { !($0.slots.values.contains(knit.id) && ($0.slots.values.contains(indigo.id) || $0.slots.values.contains(blue.id))) })
    }
    @Test("S3-U28 heat") func u28() throws {
        let f = try loadFixture()
        for o in Occasion.allCases {
            for c in cands(.init(occasion: o, weatherFeel: .hot), f.items) {
                #expect(!items(of: c, in: f.items).contains { ($0.tags.warmth ?? 0) >= 3 }, "\(o)")
            }
        }
        // a pinned warmth-3 piece skips the filter but the hard check still drops every outfit
        let knit = mk("Chunky knit", .top, .sweater, [.brown], dc: [.casual], f: 2, fabric: .knit, warmth: 3)
        let r = run(.init(occasion: .casualDay, weatherFeel: .hot, mustIncludeItemIds: [knit.id]), basics() + [knit])
        #expect(r.outfits.isEmpty)
    }
    @Test("S3-U29 all one neutral scores lower") func u29() {
        let tee = mk("Black tee", .top, .tshirt, [.black], f: 3), pants = mk("Black pants", .bottom, .chinos, [.black], f: 3)
        let blackShoes = mk("Black shoes", .footwear, .sneakers, [.black], f: 3)
        let whiteShoes = mk("White sneakers", .footwear, .sneakers, [.white], f: 3)
        let cs = cands(.init(occasion: .casualDay), [tee, pants, blackShoes, whiteShoes])
        let mono = cs.first { $0.slots[.footwear] == blackShoes.id }!, mixed = cs.first { $0.slots[.footwear] == whiteShoes.id }!
        #expect(mono.score < mixed.score)
        #expect(mono.scoreParts["colourHarmony"]! < mixed.scoreParts["colourHarmony"]!)
        #expect(cs.first?.slots[.footwear] == whiteShoes.id)
    }
    @Test("cold needs a warm layer: light top alone is never offered") func coldCover() {
        let all = basics()   // light shirt only, no outerwear
        #expect(cands(.init(occasion: .casualDay, weatherFeel: .cold), all).isEmpty)
        let r = run(.init(occasion: .casualDay, weatherFeel: .cold), all)
        #expect(r.outfits.isEmpty)
    }

    // MARK: scoring and output
    @Test("S3-U30 exclusion") func u30() throws {
        let f = try loadFixture()
        let a = run(.diwali, f.items)
        #expect(a.outfits.count == 3)
        let b = run(.diwali, f.items, ctx(exclude: Set(a.outfits.map(\.key))))
        #expect(!b.outfits.isEmpty)
        #expect(Set(a.outfits.map(\.key)).isDisjoint(with: Set(b.outfits.map(\.key))))
        let c = run(.diwali, f.items, ctx(exclude: Set(a.outfits.map(\.key)).union(b.outfits.map(\.key))))
        #expect(Set(c.outfits.map(\.key)).isDisjoint(with: Set(a.outfits.map(\.key)).union(b.outfits.map(\.key))))
    }
    @Test("S3-U31 diversity") func u31() throws {
        let f = try loadFixture()
        for o in [Occasion.casualDay, .festival, .office, .party] {
            let r = run(.init(occasion: o, weatherFeel: .mild), f.items, count: 8)
            let sets = r.outfits.map { Set(core(of: $0, in: f.items).filter { $0.cat != .footwear }.map(\.id)) }
            for i in sets.indices { for j in sets.indices where j > i { #expect(sets[i].intersection(sets[j]).count <= 1, "\(o)") } }
        }
    }
    @Test("S3-U32 deterministic") func u32() throws {
        let f = try loadFixture()
        let intent = OccasionIntent(occasion: .party, timeOfDay: .evening, weatherFeel: .cold)
        #expect(run(intent, f.items, ctx(seed: 99)) == run(intent, f.items, ctx(seed: 99)))
        #expect(run(intent, f.items, ctx(seed: 99)) == run(intent, f.items.reversed(), ctx(seed: 99)))
        #expect(run(intent, f.items, ctx(seed: 99)).outfits.count > 0)
    }
    @Test("seed changes the variety term, nothing else") func seedVaries() throws {
        let f = try loadFixture()
        let a = OutfitEngine.candidates(intent: .diwali, items: f.items, context: ctx(seed: 1))
        let b = OutfitEngine.candidates(intent: .diwali, items: f.items, context: ctx(seed: 2))
        #expect(Set(a.map(\.key)) == Set(b.map(\.key)))
        #expect(a.map(\.score) != b.map(\.score))
    }
    @Test("S3-U33 score parts in range, total is the weighted sum") func u33() throws {
        let f = try loadFixture(), w = ScoreWeights.standard.asDictionary
        let r = run(.diwali, f.items, count: 5)
        #expect(!r.outfits.isEmpty)
        for o in r.outfits {
            #expect(Set(o.scoreParts.keys) == Set(w.keys))
            for (_, v) in o.scoreParts { #expect((0...1).contains(v)) }
            #expect(abs(o.score - w.reduce(0) { $0 + $1.value * o.scoreParts[$1.key]! }) < 1e-9)
        }
    }
    @Test("S3-U34 pair weight has effect") func u34() {
        let a = mk("A", .top, .shirt, [.white]), b = mk("B", .top, .shirt, [.white])
        let bottom = mk("Bottom", .bottom, .chinos, [.black]), shoes = mk("Shoes", .footwear, .sneakers, [.white])
        let pairs = [PairKey(a.id, bottom.id): 0.9, PairKey(a.id, shoes.id): 0.9]
        var w = ScoreWeights.standard; w.variety = 0   // isolate the term under test
        let cs = OutfitEngine.candidates(intent: .init(occasion: .casualDay), items: [a, b, bottom, shoes], context: ctx(pairs: pairs), weights: w)
        #expect(cs.count == 2)
        #expect(cs[0].slots[.top] == a.id)
        #expect(cs[0].scoreParts["pairWeight"]! > cs[1].scoreParts["pairWeight"]!)
        #expect(cs[1].scoreParts["pairWeight"] == 0.5)
    }
    @Test("S3-U35 freshness has effect") func u35() {
        let worn = mk("Worn", .top, .shirt, [.white], worn: testToday.addingTimeInterval(-3 * 86_400))
        let fresh = mk("Fresh", .top, .shirt, [.white])
        let bottom = mk("Bottom", .bottom, .chinos, [.black]), shoes = mk("Shoes", .footwear, .sneakers, [.white])
        var w = ScoreWeights.standard; w.variety = 0
        let cs = OutfitEngine.candidates(intent: .init(occasion: .casualDay), items: [worn, fresh, bottom, shoes], context: ctx(), weights: w)
        #expect(cs.count == 2)
        #expect(cs[0].slots[.top] == fresh.id)
        #expect(cs[0].scoreParts["freshness"] == 1 && cs[1].scoreParts["freshness"]! < 1)
    }
    @Test("S3-U36 outfit key ignores order") func u36() {
        let ids = (0..<4).map { _ in UUID() }
        #expect(OutfitKey(ids) == OutfitKey(ids.reversed()))
        #expect(OutfitKey(ids) != OutfitKey(Array(ids.dropLast())))
        #expect(PairKey(ids[0], ids[1]) == PairKey(ids[1], ids[0]))
        let a = mk("A", .top, .shirt), b = mk("B", .bottom, .chinos), s = mk("S", .footwear, .sneakers)
        let o = run(.init(occasion: .casualDay), [a, b, s]).outfits[0]
        #expect(o.key == OutfitKey([s.id, a.id, b.id]))
    }
    @Test("S3-U37 speed: 200 items") func u37() {
        var g: UInt64 = 12345
        func next() -> Int { g = g &* 6364136223846793005 &+ 1442695040888963407; return Int(g >> 33) }
        let cols: [ColorName] = [.black, .white, .navy, .rust, .olive, .cream, .grey, .brown, .teal, .maroon]
        var all: [EngineItem] = []
        for i in 0..<200 {
            let c = cols[next() % cols.count], f = 2 + next() % 2
            switch i % 5 {
            case 0, 1: all.append(mk("Top \(i)", .top, .shirt, [c], dc: [.casual, .smartCasual], f: f))
            case 2: all.append(mk("Bottom \(i)", .bottom, .chinos, [c], dc: [.casual, .smartCasual], f: f))
            case 3: all.append(mk("Shoes \(i)", .footwear, .sneakers, [c], dc: [.casual, .smartCasual], f: f))
            default: all.append(mk("Acc \(i)", .accessory, .watch, [c], f: f))
            }
        }
        let intent = OccasionIntent(occasion: .casualDay, weatherFeel: .mild)
        _ = run(intent, all)  // warm-up
        var best = Double.infinity
        for _ in 0..<3 {
            let t0 = ContinuousClock.now
            let r = run(intent, all)
            let d = ContinuousClock.now - t0
            best = min(best, Double(d.components.seconds) * 1000 + Double(d.components.attoseconds) / 1e15)
            #expect(r.outfits.count == 3)
        }
        #if DEBUG
        #expect(best < 1500, "debug build is unoptimised; the 100 ms bound is checked in release: \(best) ms")
        #else
        #expect(best < 100, "\(best) ms")
        #endif
        print("S3-U37 best of 3: \(best) ms")
    }

    // MARK: swaps and debug output
    @Test("alternatives swap one slot only") func alternatives() throws {
        let f = try loadFixture()
        let r = run(.diwali, f.items)
        let o = r.outfits[0]
        let alts = OutfitEngine.alternatives(for: .footwear, in: o, intent: .diwali, items: f.items, context: ctx())
        #expect(!alts.isEmpty)
        for a in alts {
            #expect(a.slots[.footwear] != o.slots[.footwear])
            for (s, id) in o.slots where s != .footwear { #expect(a.slots[s] == id) }
            #expect(a.score <= alts[0].score + 1e-12)
        }
        let none = OutfitEngine.alternatives(for: .setTop, in: o, intent: .diwali, items: f.items, context: ctx())
        #expect(none.isEmpty)
        let ex = OutfitEngine.alternatives(for: .footwear, in: o, intent: .diwali, items: f.items,
                                           context: ctx(exclude: Set(alts.map(\.key))))
        #expect(Set(ex.map(\.key)).isDisjoint(with: Set(alts.map(\.key))))
    }
    @Test("debug description shows score parts and reasons") func debugText() throws {
        let f = try loadFixture()
        let r = run(.init(occasion: .interview), f.items)
        let text = r.debugDescription(items: f.items)
        #expect(text.contains("occasionFit") && text.contains("colourHarmony") && text.contains("freshness"))
        #expect(text.contains("wrongDressCode") && text.contains("Light blue oxford shirt"))
    }
    @Test("S3-I03 engine sources import no app frameworks") func i03() throws {
        let dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/StyleEngine/Engine")
        let files = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil).filter { $0.pathExtension == "swift" }
        #expect(!files.isEmpty)
        for u in files {
            let s = try String(contentsOf: u, encoding: .utf8)
            for bad in ["import SwiftUI", "import SwiftData", "import UIKit", "import FoundationModels", "import Vision"] {
                #expect(!s.contains(bad), "\(u.lastPathComponent) \(bad)")
            }
        }
    }
}
