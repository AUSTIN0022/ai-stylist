import CoreGraphics
import Foundation
import Testing
@testable import StyleEngine

// Sprint 5 package tests (SPRINT_5_TESTS.md): canvas state, wear window, pair weights, set linking.

private func near(_ a: Double, _ b: Double, _ eps: Double = 1e-9) -> Bool { abs(a - b) < eps }
private let day: TimeInterval = 86_400

@Suite("S5 canvas state")
struct S5CanvasTests {
    @Test("S5-U01 positions are fractions") func fractions() throws {
        var c = OutfitCanvas()
        let id = UUID()
        c.place(id, at: CGPoint(x: 150, y: 200), in: CGSize(width: 300, height: 400))
        let p = try #require(c.items.first)
        #expect(near(p.x, 0.5) && near(p.y, 0.5))
        let big = try #require(c.point(of: id, in: CGSize(width: 600, height: 800)))
        #expect(near(big.x, 300) && near(big.y, 400))
    }

    @Test("S5-U02 scale clamp") func scaleClamp() {
        var c = OutfitCanvas(); let id = UUID()
        c.place(id, at: .zero, in: CGSize(width: 100, height: 100))
        c.scale(id, to: 0.1); #expect(near(c.items[0].scale, 0.3))
        c.scale(id, to: 5); #expect(near(c.items[0].scale, 2.5))
        c.scale(id, to: 1.4); #expect(near(c.items[0].scale, 1.4))
    }

    @Test("S5-U03 bounds clamp keeps a third on the canvas") func bounds() {
        var c = OutfitCanvas(); let id = UUID()
        let size = CGSize(width: 300, height: 400)
        c.place(id, at: CGPoint(x: 150, y: 200), in: size)
        c.move(id, by: CGSize(width: 10_000, height: -10_000), in: size)
        let p = c.items[0]
        let half = OutfitCanvas.baseSize * p.scale / 2
        // Visible part of the item's width / height: at least a third of it.
        #expect((1 - (p.x - half)) >= 2 * half / 3 - 1e-9)
        #expect((p.y + half) >= 2 * half / 3 - 1e-9)
        c.moveTo(id, x: -5, y: 9)
        let q = c.items[0]
        #expect((q.x + half) >= 2 * half / 3 - 1e-9)
        #expect((1 - (q.y - half)) >= 2 * half / 3 - 1e-9)
    }

    @Test("S5-U04 bring to front") func front() {
        var c = OutfitCanvas(); let a = UUID(), b = UUID(), d = UUID()
        for id in [a, b, d] { c.place(id, at: .zero, in: CGSize(width: 10, height: 10)) }
        c.bringToFront(a)
        #expect(c.items.first { $0.itemId == a }!.z == c.items.map(\.z).max())
        #expect(Set(c.items.map(\.z)).count == 3)
        c.sendToBack(a)
        #expect(c.items.first { $0.itemId == a }!.z == c.items.map(\.z).min())
    }

    @Test("S5-U05 remove from canvas only removes the placement") func remove() {
        let shirt = mk("Shirt", .top, .shirt)
        let wardrobe = [shirt]
        var c = OutfitCanvas()
        c.add(shirt, using: wardrobe)
        c.remove(shirt.id)
        #expect(c.items.isEmpty)
        #expect(wardrobe.count == 1 && wardrobe[0] == shirt)
    }

    @Test("S5-U06 slot inference") func slots() {
        let shirt = mk("Shirt", .top, .shirt), chinos = mk("Chinos", .bottom, .chinos)
        let sneakers = mk("Sneakers", .footwear, .sneakers), hoodie = mk("Hoodie", .top, .hoodie)
        let tee = mk("Tee", .top, .tshirt), watch = mk("Watch", .accessory, .watch)
        let s = OutfitSlots.infer([shirt, chinos, sneakers, hoodie, watch])
        #expect(s[shirt.id] == .top && s[chinos.id] == .bottom && s[sneakers.id] == .footwear)
        #expect(s[hoodie.id] == .outerwear && s[watch.id] == .accessory1)
        // Second top: the tee goes under the shirt, whichever comes first.
        let t = OutfitSlots.infer([tee, shirt])
        #expect(t[shirt.id] == .top && t[tee.id] == .baseLayer)
        // Set members by role.
        let g = UUID()
        let kurta = mk("Kurta", .top, .kurta, group: g, role: .kurta)
        let pyjama = mk("Pyjama", .bottom, .pyjama, group: g, role: .kurtaBottom)
        let k = OutfitSlots.infer([kurta, pyjama])
        #expect(k[kurta.id] == .setTop && k[pyjama.id] == .setBottom)
    }

    @Test("S5-U07 tap-to-add lands at the default card position, once") func defaultPosition() throws {
        let shirt = mk("Shirt", .top, .shirt), chinos = mk("Chinos", .bottom, .chinos), shoes = mk("Shoes", .footwear, .sneakers)
        let all = [shirt, chinos, shoes]
        var c = OutfitCanvas()
        for i in all { c.add(i, using: all) }
        c.add(shirt, using: all)
        #expect(c.items.count == 3)
        let unit = CGSize(width: 1, height: 1), present: Set<Slot> = [.top, .bottom, .footwear]
        for (i, slot) in [(shirt, Slot.top), (chinos, .bottom), (shoes, .footwear)] {
            let box = CardLayout.box(slot, in: unit, slots: present)
            let p = try #require(c.items.first { $0.itemId == i.id })
            #expect(near(p.x, box.midX) && near(p.y, box.midY), "\(slot)")
        }
    }

    @Test("S5 adding a second bottom replaces the first") func replace() {
        let a = mk("A", .bottom, .chinos), b = mk("B", .bottom, .jeans)
        var c = OutfitCanvas()
        c.add(a, using: [a, b]); c.add(b, using: [a, b])
        #expect(c.items.map(\.itemId) == [b.id])
    }

    @Test("S5 canvas from saved slots and JSON round trip") func fromSlots() throws {
        let top = UUID(), bottom = UUID()
        let c = OutfitCanvas(slots: [.top: top, .bottom: bottom])
        #expect(Set(c.items.map(\.itemId)) == [top, bottom])
        let back = try JSONDecoder().decode(OutfitCanvas.self, from: JSONEncoder().encode(c))
        #expect(back == c)
    }
}

@Suite("S5 wear window")
struct S5WearTests {
    @Test("S5-U10 recently-worn window: tops only, 2 days") func window() {
        let yesterday = testToday.addingTimeInterval(-day), threeDays = testToday.addingTimeInterval(-3 * day)
        let wornTop = mk("Worn top", .top, .shirt, [.white], worn: yesterday)
        let oldTop = mk("Old top", .top, .shirt, [.cream], worn: threeDays)
        let otherTop = mk("Other top", .top, .polo, [.olive])
        let wornShoes = mk("Worn shoes", .footwear, .sneakers, [.white], worn: yesterday)
        let otherShoes = mk("Other shoes", .footwear, .loafers, [.brown])
        let wornJacket = mk("Worn jacket", .outerwear, .jacket, [.navy], worn: yesterday)
        let otherJacket = mk("Other jacket", .outerwear, .blazer, [.grey])
        let wornWatch = mk("Worn watch", .accessory, .watch, [.silver], worn: yesterday)
        let otherWatch = mk("Other watch", .accessory, .watch, [.gold])
        let all = [wornTop, oldTop, otherTop, mk("Bottom", .bottom, .chinos, [.black]),
                   wornShoes, otherShoes, wornJacket, otherJacket, wornWatch, otherWatch]
        let r = run(OccasionIntent(occasion: .casualDay), all)
        #expect(r.rejected[wornTop.id] == .wornRecently)
        #expect(r.rejected[oldTop.id] == nil)
        for i in [wornShoes, wornJacket, wornWatch] { #expect(r.rejected[i.id] == nil, "\(i.name)") }
    }
}

@Suite("S5 pair weights")
struct S5PairWeightTests {
    let a = UUID(), b = UUID(), c = UUID()
    func w(_ ws: [PairKey: Double], _ x: UUID, _ y: UUID) -> Double { PairWeights.value(ws, x, y) }

    @Test("S5-U11 no events: every pair 0.5") func start() {
        let ws = PairWeights.compute([])
        #expect(w(ws, a, b) == 0.5 && w(ws, b, c) == 0.5)
    }

    @Test("S5-U12 saved outfit: each pair 0.60") func saved() {
        let ws = PairWeights.compute([.saved([a, b, c])])
        for (x, y) in [(a, b), (a, c), (b, c)] { #expect(near(w(ws, x, y), 0.60)) }
    }

    @Test("S5-U13 worn: +0.15") func worn() {
        let ws = PairWeights.compute([.worn([a, b])])
        #expect(near(w(ws, a, b), 0.65))
    }

    @Test("S5-U14 rejected: -0.03") func rejected() {
        let ws = PairWeights.compute([.rejected([a, b])])
        #expect(near(w(ws, a, b), 0.47))
    }

    @Test("S5-U15 swapped: removed -0.10, replacement +0.05") func swapped() {
        let x = UUID(), y = UUID()
        let ws = PairWeights.compute([.swapped(removed: x, added: y, others: [a, b])])
        #expect(near(w(ws, x, a), 0.40) && near(w(ws, x, b), 0.40))
        #expect(near(w(ws, y, a), 0.55) && near(w(ws, y, b), 0.55))
        #expect(w(ws, a, b) == 0.5)
    }

    @Test("S5-U16 clamp and recompute") func clamp() {
        let saves = PairWeights.compute(Array(repeating: .saved([a, b]), count: 20))
        #expect(w(saves, a, b) == 1.0)
        let rejects = PairWeights.compute(Array(repeating: .rejected([a, b]), count: 40))
        #expect(near(w(rejects, a, b), 0.1))
        let events: [LearningEvent] = [.saved([a, b, c]), .rejected([a, c]), .worn([b, c])]
        #expect(PairWeights.compute(events) == PairWeights.compute(events))
    }

    @Test("S5 engine: a boosted pair ranks above an otherwise equal one") func ranking() {
        let shirt = mk("Rust shirt", .top, .shirt, [.rust])
        let linen = mk("Brown linen", .bottom, .trousers, [.brown], fabric: .linen)
        let chinos = mk("Black chinos", .bottom, .chinos, [.black])
        let shoes = mk("Shoes", .footwear, .loafers, [.tan])
        let all = [shirt, linen, chinos, shoes]
        let before = run(.diwali, all, ctx(pairs: [:]), count: 5)
        let ws = PairWeights.compute(Array(repeating: .saved([shirt.id, linen.id]), count: 3))
        let after = run(.diwali, all, ctx(pairs: ws), count: 5)
        func rank(_ r: EngineResult, _ id: UUID) -> Int? { r.outfits.firstIndex { $0.slots.values.contains(id) && $0.slots.values.contains(shirt.id) } }
        #expect(rank(before, linen.id) != nil && rank(after, linen.id) == 0)
        #expect((rank(after, chinos.id) ?? 99) > 0)
    }
}

@Suite("S5 set linking")
struct S5SetLinkTests {
    @Test("S5-U17 link gives roles by category") func link() throws {
        let kurta = mk("Kurta", .top, .kurta), pyjama = mk("Pyjama", .bottom, .pyjama)
        let roles = try SetLink.roles(for: [kurta, pyjama]).get()
        #expect(roles == [kurta.id: .kurta, pyjama.id: .kurtaBottom])
        let blouse = mk("Blouse", .top, .blouse), saree = mk("Saree", .onePiece, .saree)
        #expect(try SetLink.roles(for: [blouse, saree]).get() == [blouse.id: .blouse, saree.id: .saree])
        let choli = mk("Choli", .top, .choli), skirt = mk("Lehenga", .bottom, .lehengaSkirt), dupatta = mk("Dupatta", .accessory, .dupatta)
        #expect(try SetLink.roles(for: [choli, skirt, dupatta]).get() == [choli.id: .choli, skirt.id: .lehengaSkirt, dupatta.id: .dupatta])
    }

    @Test("S5-U19 invalid links are refused with a reason") func invalid() {
        let t1 = mk("Kurta", .top, .kurta), t2 = mk("Shirt", .top, .shirt)
        if case .failure(let e) = SetLink.roles(for: [t1, t2]) { #expect(!e.reason.isEmpty) } else { Issue.record("two tops linked") }
        if case .failure(let e) = SetLink.roles(for: [t1]) { #expect(!e.reason.isEmpty) } else { Issue.record("single item linked") }
        let shoes = mk("Juttis", .footwear, .juttis)
        if case .failure = SetLink.roles(for: [t1, shoes]) {} else { Issue.record("footwear linked") }
    }

    @Test("S5 linked set is always suggested together") func together() {
        let g = UUID()
        let kurta = mk("Kurta", .top, .kurta, [.cream], dc: [.festive, .smartCasual], group: g, role: .kurta, origin: .indian)
        let pyjama = mk("Pyjama", .bottom, .pyjama, [.white], dc: [.festive, .smartCasual], group: g, role: .kurtaBottom, origin: .indian)
        let all = basics() + [kurta, pyjama, mk("Jeans", .bottom, .jeans, [.blue]), mk("Polo", .top, .polo, [.olive])]
        var intent = OccasionIntent.diwali; intent.preferIndian = true
        let r = run(intent, all, nil, count: 5)
        #expect(!r.outfits.isEmpty)
        for o in r.outfits {
            let ids = Set(o.slots.values)
            #expect(ids.contains(kurta.id) == ids.contains(pyjama.id))
        }
        #expect(r.outfits.contains { Set($0.slots.values).contains(kurta.id) })
    }
}

@Suite("S5 learning check (fixture wardrobe)")
struct S5LearningCheckTests {
    /// SPRINT_5_TESTS.md eval: save 5 outfits and reject 5, then re-run the Diwali and office requests.
    /// Pass: top results shift toward saved pairs; no single pair appears in all three results.
    @Test("learning is gentle") func gentle() throws {
        let f = try loadFixture()
        let c = EngineContext(today: Date(timeIntervalSince1970: 1_794_000_000), seed: 20261114)
        let training: [OccasionIntent] = [
            .init(occasion: .casualDay, weatherFeel: .mild), .init(occasion: .date, timeOfDay: .evening, weatherFeel: .mild),
            .init(occasion: .party, timeOfDay: .evening, weatherFeel: .mild), .init(occasion: .travel, weatherFeel: .mild),
            .init(occasion: .festival, weatherFeel: .mild),
        ]
        var events: [LearningEvent] = []
        for t in training {
            let r = OutfitEngine.generate(intent: t, items: f.items, context: c)
            if let a = r.outfits.first { events.append(.saved(a.itemIds)) }
            if r.outfits.count > 1 { events.append(.rejected(r.outfits[1].itemIds)) }
        }
        let weights = PairWeights.compute(events)
        let savedPairs = Set(events.compactMap { e -> [PairKey]? in
            guard case .saved(let ids) = e else { return nil }
            return ids.flatMap { a in ids.compactMap { b in a.uuidString < b.uuidString ? PairKey(a, b) : nil } }
        }.joined())
        var log = ""
        for (title, intent) in [("Diwali", OccasionIntent.diwali), ("Office", OccasionIntent(occasion: .office, weatherFeel: .mild))] {
            let before = OutfitEngine.generate(intent: intent, items: f.items, context: c).outfits
            var learned = c; learned.pairWeights = weights
            let after = OutfitEngine.generate(intent: intent, items: f.items, context: learned).outfits
            let accessory = Set(f.items.filter { $0.tags.category == .accessory }.map(\.id))
            func pairs(_ o: OutfitCandidate) -> Set<PairKey> {
                let ids = o.itemIds.filter { !accessory.contains($0) }; return Set(ids.flatMap { a in ids.compactMap { b in a.uuidString < b.uuidString ? PairKey(a, b) : nil } })
            }
            func common(_ os: [OutfitCandidate]) -> Set<PairKey> { os.map(pairs).dropFirst().reduce(os.first.map(pairs) ?? []) { $0.intersection($1) } }
            func savedShare(_ os: [OutfitCandidate]) -> Int { os.reduce(0) { $0 + pairs($1).intersection(savedPairs).count } }
            log += "\(title): saved pairs in top 3 before \(savedShare(before)), after \(savedShare(after)); clothing pairs common to all 3: before \(common(before).count), after \(common(after).count)\n"
            func meanPairPart(_ os: [OutfitCandidate]) -> Double { os.reduce(0) { $0 + ($1.scoreParts["pairWeight"] ?? 0) } / Double(max(os.count, 1)) }
            log += "\(title): mean pairWeight part before \(String(format: "%.3f", meanPairPart(before))), after \(String(format: "%.3f", meanPairPart(after)))\n"
            #expect(meanPairPart(after) > meanPairPart(before), "\(title): the learned weights never reached the top results")
            #expect(after.count == 3, "\(title)")
            #expect(savedShare(after) >= savedShare(before), "\(title): learning moved results away from saved pairs")
            #expect(common(after).isEmpty, "\(title): one pair appears in all three results")
        }
        print(log)
    }
}
