import Foundation
import Testing
@testable import StyleEngine

@Suite("S3 scenarios on the 45-item fixture") struct EngineScenarioTests {
    let f: Fixture
    init() throws { f = try loadFixture() }

    func keys(_ o: OutfitCandidate) -> Set<String> { Set(o.slots.values.map { f.key(of: $0) }) }
    func isKnitOrOuter(_ i: EngineItem) -> Bool {
        i.cat == .outerwear || [Fabric.knit, .wool, .fleece].contains(i.tags.fabric ?? .unknown) || [Subcategory.sweater, .hoodie].contains(i.sub ?? .other)
    }

    @Test("S3-SC01 festival evening indoor mild: rust shirt with black chinos or brown linen trousers in top 3")
    func sc01() {
        let r = run(.diwali, f.items)
        #expect(r.outfits.count == 3)
        #expect(r.outfits.contains { o in
            let k = keys(o)
            return k.contains("shirt_rust_mandarin") && (k.contains("pants_black_chinos_relaxed") || k.contains("pants_black_chinos_straight") || k.contains("pants_brown_linen"))
        }, "\(r.outfits.map(keys))")
    }
    @Test("S3-SC02 fireworks: no open-toe footwear") func sc02() {
        let r = run(.init(occasion: .festival, timeOfDay: .evening, setting: .indoor, weatherFeel: .mild, flags: [.fireworks]), f.items, count: 10)
        #expect(!r.outfits.isEmpty)
        for o in r.outfits { #expect(!items(of: o, in: f.items).contains(where: isOpenToe)) }
        #expect(r.rejected[f.id("shoes_birkenstock_sandals")] == .openToeBlocked)
    }
    @Test("S3-SC03 interview") func sc03() {
        let r = run(.init(occasion: .interview), f.items, count: 6)
        #expect(!r.outfits.isEmpty)
        #expect(r.outfits.contains { keys($0).contains("shirt_light_blue_oxford") })
        #expect(keys(r.outfits[0]).contains("shirt_light_blue_oxford"))
        let banned: Set<String> = ["tee_green_graphic", "tee_black_graphic", "shoes_black_slides", "shoes_black_sambas"]
        for o in r.outfits { #expect(keys(o).isDisjoint(with: banned)) }
        for o in r.outfits {
            let bottoms = items(of: o, in: f.items).filter { $0.cat == .bottom }
            #expect(bottoms.allSatisfy { $0.sub == .chinos || $0.sub == .trousers })
        }
    }
    @Test("S3-SC04 casual day hot: no knitwear, corduroy or outerwear") func sc04() {
        let r = run(.init(occasion: .casualDay, weatherFeel: .hot), f.items, count: 10)
        #expect(r.outfits.count >= 3)
        for o in r.outfits {
            for i in items(of: o, in: f.items) {
                #expect(!isKnitOrOuter(i), "\(i.name)")
                #expect(i.tags.fabric != .corduroy, "\(i.name)")
                #expect(i.cat != .outerwear)
            }
        }
    }
    @Test("S3-SC05 date evening cold: knit or outerwear in every result") func sc05() {
        let r = run(.init(occasion: .date, timeOfDay: .evening, weatherFeel: .cold), f.items, count: 6)
        #expect(!r.outfits.isEmpty)
        for o in r.outfits { #expect(items(of: o, in: f.items).contains(where: isKnitOrOuter), "\(keys(o))") }
    }
    @Test("S3-SC06 office: smart casual or above, no graphic, no slides") func sc06() {
        let r = run(.init(occasion: .office), f.items, count: 6)
        #expect(r.outfits.count >= 3)
        let formalish: Set<DressCode> = [.smartCasual, .businessCasual, .formal]
        for o in r.outfits { for i in core(of: o, in: f.items) {
            #expect(!formalish.isDisjoint(with: i.tags.dressCodes ?? []), "\(i.name)")
            #expect(i.tags.pattern != .graphic && i.sub != .slides)
        } }
    }
    @Test("S3-SC07 festival preferIndian: kurta + pyjama + juttis or sandals in top 3") func sc07() {
        let r = run(.init(occasion: .festival, timeOfDay: .evening, preferIndian: true), f.items)
        #expect(r.outfits.contains { o in
            let k = keys(o)
            return k.contains("kurta_mustard") && k.contains("pyjama_cream") && (k.contains("juttis_tan") || k.contains("shoes_birkenstock_sandals"))
        }, "\(r.outfits.map(keys))")
    }
    @Test("S3-SC08 no footwear fixture") func sc08() throws {
        let nf = try loadFixture("wardrobe_nofootwear")
        for o in Occasion.allCases where o != .gym {
            let r = run(.init(occasion: o), nf.items)
            #expect(r.outfits.allSatisfy { $0.slots[.footwear] == nil }, "\(o)")   // fix round 1: built without shoes
        }
        let r = run(.init(occasion: .casualDay), nf.items)
        #expect(!r.outfits.isEmpty && r.softMissing == [.footwear])
    }
    @Test("S3-SC09 avoid jeans") func sc09() {
        let r = run(.init(occasion: .casualDay, avoid: [.subcategory(.jeans)]), f.items, count: 10)
        #expect(!r.outfits.isEmpty)
        for o in r.outfits { #expect(!items(of: o, in: f.items).contains { $0.sub == .jeans }) }
        let jeans = f.items.filter { $0.sub == .jeans }
        #expect(jeans.count == 4)
        for j in jeans { #expect(r.rejected[j.id] == .avoided, "\(j.name)") }
    }
    @Test("S3-SC10 cold, pinned olive corduroy") func sc10() {
        let pin = f.id("pants_cord_olive")
        let r = run(.init(occasion: .casualDay, weatherFeel: .cold, mustIncludeItemIds: [pin]), f.items, count: 5)
        #expect(r.outfits.count >= 2)
        for o in r.outfits { #expect(o.slots[.bottom] == pin) }
    }
    @Test("S3-SC11 home: formality 1-2, slides allowed") func sc11() {
        let r = run(.init(occasion: .home), f.items, count: 5)
        #expect(!r.outfits.isEmpty)
        #expect(r.rejected[f.id("shoes_black_slides")] == nil)
        for o in r.outfits { for i in core(of: o, in: f.items) { #expect((1...2).contains(i.tags.formality!), "\(i.name)") } }
        #expect(r.outfits.contains { keys($0).contains("shoes_black_slides") })
    }
    @Test("S3-SC12 party: at most one statement piece, never all one neutral") func sc12() {
        for w in [WeatherFeel.mild, .cold] {
            let r = run(.init(occasion: .party, timeOfDay: .evening, weatherFeel: w), f.items, count: 6)
            #expect(!r.outfits.isEmpty)
            for o in r.outfits {
                let c = core(of: o, in: f.items)
                #expect(c.filter(\.isNonSolidOrStatement).count <= 1)
                #expect(Set(c.compactMap(\.colors.first)).count > 1, "\(keys(o))")
            }
        }
    }
    @Test("cold interview or wedding: nothing warm fits, so the engine says it needs a layer") func coldNeedsLayer() {
        for o in [Occasion.interview, .weddingGuest] {
            let r = run(.init(occasion: o, weatherFeel: .cold), f.items)
            #expect(r.outfits.isEmpty, "\(o)")
            #expect(r.missing == [.outerwear], "\(o)")
        }
    }
    @Test("no occasion on the fixture returns nothing (gym excepted: nothing athletic is owned)") func nothingEmpty() {
        for o in Occasion.allCases where o != .gym {
            for w in [WeatherFeel.mild, .hot, .cold] {
                if o == .interview && w == .hot { continue }
                if w == .cold && (o == .interview || o == .weddingGuest) { continue }   // no warm layer fits: see coldNeedsLayer
                #expect(!run(.init(occasion: o, weatherFeel: w), f.items).outfits.isEmpty, "\(o) \(w)")
            }
        }
        #expect(run(.init(occasion: .gym), f.items).outfits.isEmpty)
        #expect(run(.init(occasion: .gym), f.items).missing.count > 0)
    }
}
