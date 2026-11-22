import Foundation

/// Sprint 3 outfit engine (PRD §5.5): filter, pick formulas, seed, fill, hard checks, score, diversify.
/// Pure and deterministic: the only randomness is a hash of (seed, outfit), so item order never matters.
public enum OutfitEngine {
    // MARK: Public API

    public static func generate(intent: OccasionIntent, items: [EngineItem], context: EngineContext = EngineContext(),
                                count: Int = 3, weights: ScoreWeights = .standard) -> EngineResult {
        let run = Run(intent, items, context, weights)
        let all = run.candidates()
        var kept: [OutfitCandidate] = []
        var looks = Set<[String]>()
        for c in all where kept.count < count {
            let mine = run.nonFootwear(c)
            // Twins (same category, subcategory and colour) make the same look: show it once.
            if kept.allSatisfy({ run.nonFootwear($0).intersection(mine).count <= 1 }), looks.insert(run.look(c)).inserted { kept.append(c) }
        }
        let missing = all.isEmpty ? run.missingSlots() : []
        return EngineResult(outfits: kept, rejected: run.rejected, missing: missing, kept: run.pool.map(\.id),
                            softMissing: run.noFootwear && !kept.isEmpty ? [.footwear] : [])
    }

    /// Every candidate that passed the hard checks and is not excluded, best first, before the diversity trim.
    public static func candidates(intent: OccasionIntent, items: [EngineItem], context: EngineContext = EngineContext(),
                                  weights: ScoreWeights = .standard) -> [OutfitCandidate] {
        Run(intent, items, context, weights).candidates()
    }

    /// What an outfit looks like: sorted slot/category/subcategory/primary colour. Twin items give the same look.
    public static func look(of outfit: OutfitCandidate, items: [EngineItem]) -> [String] {
        Run(OccasionIntent(occasion: .casualDay), items, EngineContext(), .standard).look(outfit)
    }

    /// Swap: other items for one slot of `outfit`, everything else unchanged, best first.
    /// Set slots and pinned items are not swappable.
    public static func alternatives(for slot: Slot, in outfit: OutfitCandidate, intent: OccasionIntent, items: [EngineItem],
                                    context: EngineContext = EngineContext(), limit: Int = 5,
                                    weights: ScoreWeights = .standard) -> [OutfitCandidate] {
        let run = Run(intent, items, context, weights)
        return run.alternatives(for: slot, in: outfit, limit: limit)
    }
}

// MARK: - Formulas (data)

struct Formula {
    let name: String
    let slots: [Slot]                 // seed slot first, then fill order
    let weather: Set<WeatherFeel>?    // nil = any
    let overlayerTop: Bool            // top slot holds an open layer over a base tee
    static let all: [Formula] = [
        Formula(name: "topBottomFootwear", slots: [.top, .bottom, .footwear], weather: nil, overlayerTop: false),
        Formula(name: "layered", slots: [.top, .baseLayer, .bottom, .footwear], weather: [.mild, .cold, .rainy, .unknown], overlayerTop: true),
        Formula(name: "withOuterwear", slots: [.top, .bottom, .footwear, .outerwear], weather: [.cold, .rainy], overlayerTop: false),
        Formula(name: "onePiece", slots: [.onePiece, .footwear], weather: nil, overlayerTop: false),
    ]
    /// Formulas offered for a weather (U17). Set formulas are built per set at run time.
    static func offered(for w: WeatherFeel) -> [Formula] { all.filter { $0.weather?.contains(w) ?? true } }
}

private let setSlotForRole: [SetRole: Slot] = [
    .kurta: .setTop, .blouse: .setTop, .choli: .setTop,
    .kurtaBottom: .setBottom, .lehengaSkirt: .setBottom,
    .dupatta: .setDrape, .saree: .setDrape,
]

extension ItemRule {
    func blocks(_ i: EngineItem) -> Bool {
        let t = i.tags
        switch self {
        case .noGraphic: return t.pattern == .graphic
        case .noSlides: return t.subcategory == .slides
        case .noDenim: return t.fabric == .denim
        case .noShorts: return t.subcategory == .shorts
        case .noSleeveless: return t.sleeve == .sleeveless
        case .closedToeOnly: return t.category == .footwear && engineIsOpenToe(i)
        case .noFormalShoes: return t.subcategory == .formalShoes
        case .plainOrSubtle:
            if t.statement == .statement { return true }
            switch t.pattern ?? .solid {
            case .solid, .textured: return false
            case .stripe, .check: return t.statement != .plain
            default: return true
            }
        }
    }
}

func engineIsOpenToe(_ i: EngineItem) -> Bool {
    i.tags.closedToe == false || (i.tags.closedToe == nil && (i.tags.subcategory == .sandals || i.tags.subcategory == .slides))
}

// MARK: - One engine run

struct Run {
    struct Eff { var dressCodes: [DressCode]; var range: ClosedRange<Int>; var rules: [ItemRule]; var boosts: [Boost] }
    struct Plan { let name: String; let fixed: [Slot: UUID]; let slots: [Slot]; let overlayerTop: Bool; let setFamily: Bool }
    typealias Chosen = [Slot: EngineItem]

    let intent: OccasionIntent, ctx: EngineContext, w: ScoreWeights
    let eff: Eff
    let items: [EngineItem]                // sorted by id: no input-order dependence
    let byId: [UUID: EngineItem]
    let pinned: Set<UUID>
    private(set) var rejected: [UUID: RejectReason] = [:]
    private(set) var pool: [EngineItem] = []
    private var accessories: [EngineItem] = []

    init(_ intent: OccasionIntent, _ input: [EngineItem], _ ctx: EngineContext, _ w: ScoreWeights) {
        self.intent = intent; self.ctx = ctx; self.w = w
        let row = OccasionTable.rows[intent.occasion] ?? OccasionTable.rows[.casualDay]!
        var rules = row.rules
        for f in intent.flags.sorted(by: { $0.rawValue < $1.rawValue }) {
            rules += OccasionTable.flagRules[f] ?? []
            rules += row.ifFlag[f] ?? []
        }
        var boosts = row.boosts
        if intent.preferIndian { boosts += [.indian, .indoWestern] }
        var seen = Set<Boost>(); boosts = boosts.filter { seen.insert($0).inserted }
        let lo = intent.formalityMin ?? row.formality.lowerBound, hi = intent.formalityMax ?? row.formality.upperBound
        eff = Eff(dressCodes: intent.dressCode.map { [$0] } ?? row.dressCodes, range: min(lo, hi)...max(lo, hi),
                  rules: Array(Set(rules)), boosts: boosts)
        items = input.sorted { $0.id.uuidString < $1.id.uuidString }
        byId = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        // Pinned items skip every check, and a pinned set item brings its whole set.
        var pins = Set(intent.mustIncludeItemIds)
        let groups = Set(items.filter { pins.contains($0.id) }.compactMap(\.setGroupId))
        for i in items where i.setGroupId.map(groups.contains) ?? false { pins.insert(i.id) }
        pinned = pins
        runFilters()
    }

    // MARK: Filter stage

    private func hardFilter(_ i: EngineItem) -> RejectReason? {
        let t = i.tags
        if !i.isReady || t.category == nil { return .notReady }
        for a in intent.avoid {
            switch a {
            case .colour(let c): if i.colors.contains(c) { return .avoided }
            case .subcategory(let s): if t.subcategory == s { return .avoided }
            }
        }
        if (t.dressCodes ?? []).allSatisfy({ !eff.dressCodes.contains($0) }) { return .wrongDressCode }
        let f = t.formality ?? 3
        if f < eff.range.lowerBound - 1 || f > eff.range.upperBound + 1 { return .formalityOutOfRange }
        let seasons = t.seasons ?? []
        switch intent.weatherFeel {
        case .hot:
            if (t.warmth ?? 1) >= 3 { return .tooWarm }
            if t.category == .outerwear || (!seasons.isEmpty && !seasons.contains(.summer)) { return .wrongSeason }
        case .cold:
            // Only clearly hot-weather pieces: the AI's season tags are too loose to trust here.
            if t.subcategory == .shorts || (t.category == .footwear && engineIsOpenToe(i)) { return .wrongSeason }
        default: break
        }
        if eff.rules.contains(.closedToeOnly) && ItemRule.closedToeOnly.blocks(i) { return .openToeBlocked }
        if eff.rules.contains(where: { $0 != .closedToeOnly && $0.blocks(i) }) { return .ruleBlocked }
        return nil
    }

    private mutating func runFilters() {
        var survivors: [EngineItem] = []
        for i in items {
            if pinned.contains(i.id) { survivors.append(i); continue }
            if let r = hardFilter(i) { rejected[i.id] = r } else { survivors.append(i) }
        }
        // wornRecently is soft: only when another item of the same category has not been worn lately.
        let recentUnits = Set(survivors.filter { recent($0) }.compactMap(\.setGroupId))
        func isRecent(_ i: EngineItem) -> Bool { recent(i) || (i.setGroupId.map(recentUnits.contains) ?? false) }
        var fresh: [Category: Int] = [:]
        for i in survivors where !isRecent(i) { fresh[i.tags.category!, default: 0] += 1 }
        pool = survivors.filter { i in
            if pinned.contains(i.id) || !isRecent(i) { return true }
            if fresh[i.tags.category!, default: 0] >= 1 { rejected[i.id] = .wornRecently; return false }
            return true
        }
        accessories = pool.filter { $0.tags.category == .accessory && $0.setGroupId == nil }
    }

    /// Worn in the last 2 days. Only tops and one-pieces count: shoes, layers and accessories are fine to repeat.
    private func recent(_ i: EngineItem) -> Bool {
        guard let d = i.lastWornAt, [.top, .onePiece].contains(i.tags.category) || i.setGroupId != nil else { return false }
        return ctx.today.timeIntervalSince(d) < 2 * 86_400
    }

    // MARK: Slot eligibility and pools

    private func isOverlayer(_ i: EngineItem) -> Bool {
        let t = i.tags
        guard t.category == .top, i.setGroupId == nil else { return false }
        switch t.subcategory {
        case .sweater, .hoodie: return true
        case .shirt: return t.collar != .mandarin
        default: return false
        }
    }
    private func canBase(_ i: EngineItem) -> Bool {
        let t = i.tags
        return t.category == .top && t.subcategory == .tshirt && i.setGroupId == nil
            && [.solid, .textured].contains(t.pattern ?? .solid) && t.statement != .statement
    }
    private func eligible(_ i: EngineItem, _ s: Slot, _ plan: Plan) -> Bool {
        guard i.setGroupId == nil else { return false }
        switch s {
        case .top: return plan.overlayerTop ? isOverlayer(i) : i.tags.category == .top
        case .baseLayer: return canBase(i)
        case .bottom: return i.tags.category == .bottom
        case .onePiece: return i.tags.category == .onePiece
        case .outerwear: return i.tags.category == .outerwear
        case .footwear: return i.tags.category == .footwear
        default: return false
        }
    }
    private func slotPool(_ s: Slot, _ plan: Plan) -> [EngineItem] { pool.filter { eligible($0, s, plan) } }

    /// Whole sets whose members all survived (or are pinned): slot assignment per set.
    private func setUnits() -> [[Slot: EngineItem]] {
        var groups: [UUID: [EngineItem]] = [:]
        for i in items { if let g = i.setGroupId { groups[g, default: []].append(i) } }
        let poolIds = Set(pool.map(\.id))
        var out: [[Slot: EngineItem]] = []
        for g in groups.keys.sorted(by: { $0.uuidString < $1.uuidString }) {
            let members = groups[g]!
            guard members.allSatisfy({ poolIds.contains($0.id) }) else { continue }
            var m: [Slot: EngineItem] = [:]
            for i in members {
                let s = setSlotForRole[i.tags.setRole ?? .none]
                    ?? (i.tags.category == .top ? .setTop : i.tags.category == .bottom ? .setBottom : .setDrape)
                if m[s] == nil { m[s] = i }
            }
            out.append(m)
        }
        return out
    }

    /// No footwear survived the filters: outfits are built without the slot (a soft hint, not a failure).
    var noFootwear: Bool { !pool.contains { $0.tags.category == .footwear } }

    func look(_ c: OutfitCandidate) -> [String] {
        c.slots.sorted { $0.key < $1.key }.map { s, id in
            let i = byId[id]
            return "\(s.rawValue)/\(i?.tags.category?.rawValue ?? "")/\(i?.tags.subcategory?.rawValue ?? "")/\(i.map(primary)?.rawValue ?? id.uuidString)"
        }
    }

    private func plans() -> [(Plan, [Slot: EngineItem]?)] {
        let noShoes = noFootwear
        func shoes(_ s: [Slot]) -> [Slot] { noShoes ? s.filter { $0 != .footwear } : s }
        let wf = intent.weatherFeel
        var out: [(Plan, [Slot: EngineItem]?)] = []
        for u in setUnits() {
            let fixed = u.mapValues(\.id)
            out.append((Plan(name: "set", fixed: fixed, slots: shoes([.footwear]), overlayerTop: false, setFamily: true), u))
            if wf == .cold || wf == .rainy {
                out.append((Plan(name: "setOuterwear", fixed: fixed, slots: shoes([.footwear, .outerwear]), overlayerTop: false, setFamily: true), u))
            }
        }
        for f in Formula.offered(for: wf) {
            out.append((Plan(name: f.name, fixed: [:], slots: shoes(f.slots), overlayerTop: f.overlayerTop, setFamily: false), nil))
        }
        return out
    }

    // MARK: Scoring pieces

    private func primary(_ i: EngineItem) -> ColorName { i.colors.first ?? .multicolor }

    private func boostMatch(_ b: Boost, _ i: EngineItem) -> Double {
        let t = i.tags, c = primary(i)
        switch b {
        case .fittedTops: return t.category == .top && t.fit == .slim ? 1 : 0
        case .darkBottoms: return t.category == .bottom && OccasionTable.darkColours.contains(c) ? 1 : 0
        case .warmColours: return OccasionTable.warmColours.contains(c) ? 1 : 0
        case .earthColours: return OccasionTable.earthColours.contains(c) ? 1 : 0
        case .lightColours: return OccasionTable.lightColours.contains(c) ? 1 : 0
        case .indian: return t.styleOrigin == .indian ? 1 : 0
        case .indoWestern: return t.styleOrigin == .indoWestern ? 1 : 0
        case .indianSets: return i.setGroupId != nil ? 1 : 0
        case .statementPiece: return t.statement == .statement ? 1 : 0
        }
    }

    /// How well one item suits the occasion, 0...1 (dress code and formality up to 0.8, boosts up to 0.2).
    func fit(_ i: EngineItem) -> Double {
        let t = i.tags, dcs = t.dressCodes ?? []
        let dc: Double = dcs.contains(eff.dressCodes[0]) ? 1 : dcs.contains(where: eff.dressCodes.contains) ? 0.85 : 0.3
        let f = t.formality ?? 3
        let dist = f < eff.range.lowerBound ? eff.range.lowerBound - f : f > eff.range.upperBound ? f - eff.range.upperBound : 0
        let fs = [1.0, 0.6, 0.2][min(dist, 2)]
        let bonus = min(0.2, eff.boosts.reduce(0.0) { $0 + 0.08 * boostMatch($1, i) })
        return 0.8 * (0.5 * dc + 0.5 * fs) + bonus
    }

    // MARK: Hard checks

    /// Outerwear, a warm top or one-piece, or a hoodie or sweater (the AI often tags those warmth 1).
    private func isWarmCover(_ i: EngineItem) -> Bool {
        let t = i.tags
        return t.category == .outerwear || ([.top, .onePiece].contains(t.category) && ((t.warmth ?? 1) >= 2 || t.subcategory == .hoodie || t.subcategory == .sweater))
    }

    private func nonSolid(_ i: EngineItem) -> Bool {
        !([Pattern.solid, .textured].contains(i.tags.pattern ?? .solid)) || i.tags.statement == .statement
    }

    /// Checks that hold for any subset of an outfit. `final` adds the checks that need the whole outfit.
    private func ok(_ chosen: Chosen, final: Bool) -> Bool {
        let core = chosen.values.filter { $0.tags.category != .accessory }
        if core.filter(nonSolid).count > 1 { return false }
        let fs = core.map { $0.tags.formality ?? 3 }
        if let mx = fs.max(), let mn = fs.min(), mx - mn > 2 { return false }
        if intent.weatherFeel == .hot && core.contains(where: { ($0.tags.warmth ?? 1) >= 3 }) { return false }
        if let t = chosen[.top], let b = chosen[.bottom], ColourTable.sameFamily(primary(t), primary(b)) { return false }
        if final && intent.weatherFeel == .cold {
            if !core.contains(where: isWarmCover) { return false }
        }
        return true
    }

    // MARK: Scoring

    private func harmony(_ colours: [ColorName]) -> Double {
        var sum = 0.0, n = 0.0
        for i in colours.indices { for j in colours.indices where j > i { sum += ColourTable.score(colours[i], colours[j]); n += 1 } }
        var h = n == 0 ? 0.5 : sum / n
        if colours.count > 1, Set(colours).count == 1, ColourTable.neutrals.contains(colours[0]) { h -= 0.35 }  // all one neutral
        return max(0, min(1, h))
    }

    private func variety(_ key: OutfitKey) -> Double {
        var h: UInt64 = 0xcbf29ce484222325 ^ ctx.seed
        for id in key.ids {
            withUnsafeBytes(of: id.uuid) { for b in $0 { h = (h ^ UInt64(b)) &* 0x100000001b3 } }
        }
        h = h &+ 0x9E3779B97F4A7C15
        var z = (h ^ (h >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        z ^= z >> 31
        return Double(z >> 11) / Double(1 << 53)
    }

    /// Parts over the non-accessory items; the total is exactly the weighted sum.
    private func score(_ slots: [Slot: EngineItem]) -> (Double, [String: Double]) {
        let core = slots.keys.sorted().map { slots[$0]! }.filter { $0.tags.category != .accessory }
        var occ = core.reduce(0) { $0 + fit($1) } / Double(core.count)
        // preferIndian: outfits with an Indian or Indo-western garment get a decisive lift.
        if intent.preferIndian { occ = 0.8 * occ + (core.contains { ($0.tags.styleOrigin ?? .western) != .western } ? 0.2 : 0) }
        let fs = core.map { $0.tags.formality ?? 3 }
        let spread = Double((fs.max() ?? 3) - (fs.min() ?? 3))
        var pw = 0.0, pn = 0.0
        for i in core.indices { for j in core.indices where j > i {
            pw += ctx.pairWeights[PairKey(core[i].id, core[j].id)] ?? 0.5; pn += 1
        } }
        var fresh = 1.0
        for i in core { if let d = i.lastWornAt {
            fresh = min(fresh, max(0, min(1, ctx.today.timeIntervalSince(d) / 86_400 / 7)))
        } }
        let parts: [String: Double] = [
            "occasionFit": max(0, min(1, occ)),
            "colourHarmony": harmony(core.map(primary)),
            "formalityMatch": max(0, 1 - spread / 4),
            "pairWeight": pn == 0 ? 0.5 : pw / pn,
            "freshness": fresh,
            "variety": variety(OutfitKey(core.map(\.id))),
        ]
        let wd = w.asDictionary
        return (wd.keys.sorted().reduce(0) { $0 + wd[$1]! * parts[$1]! }, parts)
    }

    // MARK: Fill

    private func rank(_ cands: [EngineItem], against chosen: Chosen, into slot: Slot) -> [EngineItem] {
        let cols = chosen.values.filter { $0.tags.category != .accessory }.map(primary)
        var scored: [(Double, EngineItem)] = []
        for c in cands {
            var trial = chosen; trial[slot] = c
            guard ok(trial, final: false) else { continue }
            let h = cols.isEmpty ? 0.5 : cols.reduce(0) { $0 + ColourTable.score(primary(c), $1) } / Double(cols.count)
            scored.append((0.5 * fit(c) + 0.5 * h, c))
        }
        scored.sort { $0.0 != $1.0 ? $0.0 > $1.0 : $0.1.id.uuidString < $1.1.id.uuidString }
        return topLooks(scored.map(\.1), 2)
    }

    /// The items of the first `n` distinct looks (twins share a look: same category, subcategory, primary colour), best first.
    /// Twins all stay, so pair weights can choose between them, but they never crowd other looks out of the cut.
    private func topLooks(_ xs: [EngineItem], _ n: Int) -> [EngineItem] {
        func key(_ i: EngineItem) -> String { "\(i.tags.category?.rawValue ?? "")/\(i.tags.subcategory?.rawValue ?? "")/\(primary(i).rawValue)" }
        var seen: [String] = []
        for x in xs where !seen.contains(key(x)) && seen.count < n { seen.append(key(x)) }
        return xs.filter { seen.contains(key($0)) }
    }

    /// Places each pinned non-set item into a distinct slot of the plan, or nil when it cannot fit.
    private func pinnedStart(_ plan: Plan) -> Chosen? {
        var start: Chosen = [:]
        for id in intent.mustIncludeItemIds {
            guard let p = byId[id], p.tags.category != .accessory else { continue }
            if p.setGroupId != nil { continue }          // handled by the set plan's fixed slots
            guard let s = plan.slots.first(where: { start[$0] == nil && eligible(p, $0, plan) }) else { return nil }
            start[s] = p
        }
        return start
    }

    /// All candidates for one plan: seeds × top 2 per remaining slot, hard-checked and scored.
    private func build(_ plan: Plan, set: [Slot: EngineItem]?) -> [OutfitCandidate] {
        let pinnedIds = Set(intent.mustIncludeItemIds.compactMap { byId[$0] }.filter { $0.setGroupId == nil && $0.tags.category != .accessory }.map(\.id))
        let pinSetGroups = Set(intent.mustIncludeItemIds.compactMap { byId[$0]?.setGroupId })
        var starts: [Chosen] = []
        if let set {
            // A pinned set item only fits its own set; other pinned items must fit the fill slots.
            if !pinSetGroups.isEmpty, !(set.values.contains { $0.setGroupId.map(pinSetGroups.contains) ?? false }) { return [] }
            guard let extra = pinnedStart(plan) else { return [] }
            starts = [set.merging(extra) { a, _ in a }]
        } else {
            if !pinSetGroups.isEmpty { return [] }          // pinned set item: only set plans
            guard let pins = pinnedStart(plan) else { return [] }
            if !pinnedIds.isEmpty, pins.count < pinnedIds.count { return [] }
            if pins[plan.slots[0]] != nil { starts = [pins] }
            else {
                let seeds = topLooks(slotPool(plan.slots[0], plan).sorted {
                    fit($0) != fit($1) ? fit($0) > fit($1) : $0.id.uuidString < $1.id.uuidString
                }, 5)
                starts = seeds.map { var c = pins; c[plan.slots[0]] = $0; return c }
            }
        }
        var states = starts.filter { ok($0, final: false) }
        let order = set != nil ? plan.slots : Array(plan.slots.dropFirst())
        for slot in order {
            var next: [Chosen] = []
            for s in states where s[slot] == nil {
                for c in rank(slotPool(slot, plan), against: s, into: slot) { var n = s; n[slot] = c; next.append(n) }
            }
            states = next + states.filter { $0[slot] != nil }
        }
        return states.filter { st in plan.slots.allSatisfy { st[$0] != nil } && ok(st, final: true) }.map { st in
            let (total, parts) = score(st)
            return OutfitCandidate(slots: st.mapValues(\.id), score: total, scoreParts: parts)
        }
    }

    /// Up to two accessories whose formality is within 1 of the outfit's average, best colour match first.
    private func withAccessories(_ c: OutfitCandidate) -> OutfitCandidate {
        let core = c.slots.values.compactMap { byId[$0] }
        let mean = Double(core.map { $0.tags.formality ?? 3 }.reduce(0, +)) / Double(max(core.count, 1))
        let cols = core.map(primary)
        let pinnedAcc = intent.mustIncludeItemIds.compactMap { byId[$0] }.filter { $0.tags.category == .accessory }
        var picked = pinnedAcc
        var seenSubs = Set(pinnedAcc.compactMap(\.tags.subcategory))
        let ranked = accessories.filter { a in
            !pinned.contains(a.id) && abs(Double(a.tags.formality ?? 3) - mean) <= 1
                && (a.tags.subcategory != .belt || c.slots[.bottom] != nil)      // a belt needs trousers, not a set
        }.map { a -> (Double, EngineItem) in
            (cols.reduce(0) { $0 + ColourTable.score(primary(a), $1) } / Double(max(cols.count, 1)) - 0.01 * abs(Double(a.tags.formality ?? 3) - mean), a)
        }.sorted { $0.0 != $1.0 ? $0.0 > $1.0 : $0.1.id.uuidString < $1.1.id.uuidString }
        for (_, a) in ranked where picked.count < 2 {
            if let s = a.tags.subcategory, !seenSubs.insert(s).inserted { continue }
            picked.append(a)
        }
        var slots = c.slots
        for (n, a) in picked.prefix(2).enumerated() { slots[n == 0 ? .accessory1 : .accessory2] = a.id }
        return OutfitCandidate(slots: slots, score: c.score, scoreParts: c.scoreParts)
    }

    // MARK: Entry points used by OutfitEngine

    func candidates() -> [OutfitCandidate] {
        var best: [OutfitKey: OutfitCandidate] = [:]
        for (plan, set) in plans() {
            for c in build(plan, set: set).map(withAccessories) where !ctx.excludeOutfits.contains(c.key) && !excludesLook(c) {
                if best[c.key].map({ $0.score < c.score }) ?? true { best[c.key] = c }
            }
        }
        return best.values.sorted {
            $0.score != $1.score ? $0.score > $1.score : $0.key.ids.map(\.uuidString).lexicographicallyPrecedes($1.key.ids.map(\.uuidString))
        }
    }

    private func excludesLook(_ c: OutfitCandidate) -> Bool { !ctx.excludeLooks.isEmpty && ctx.excludeLooks.contains(look(c)) }

    func nonFootwear(_ c: OutfitCandidate) -> Set<UUID> {
        Set(c.slots.compactMap { s, id in
            guard let i = byId[id], i.tags.category != .footwear, i.tags.category != .accessory else { return nil }
            return id
        })
    }

    /// Slots with no surviving item, for the formula that is closest to feasible.
    func missingSlots() -> [Slot] {
        var best: [Slot]? = nil
        for (plan, _) in plans() {
            let gaps = plan.slots.filter { plan.fixed[$0] == nil && slotPool($0, plan).isEmpty }
            if best == nil || gaps.count < best!.count { best = gaps }
            if gaps.isEmpty { return coldNeedsLayer() }       // feasible on paper: hard checks or exclusions emptied it
        }
        return best ?? []
    }

    /// Cold weather and nothing warm survived the filters: the missing piece is an overlayer or outerwear.
    private func coldNeedsLayer() -> [Slot] {
        guard intent.weatherFeel == .cold else { return [] }
        return pool.contains(where: isWarmCover) ? [] : [.outerwear]
    }

    func alternatives(for slot: Slot, in outfit: OutfitCandidate, limit: Int) -> [OutfitCandidate] {
        if [.setTop, .setBottom, .setDrape].contains(slot) { return [] }
        if let cur = outfit.slots[slot], pinned.contains(cur) { return [] }
        let isAcc = slot == .accessory1 || slot == .accessory2
        if outfit.slots[slot] == nil && !isAcc { return [] }
        let layered = outfit.slots[.baseLayer] != nil
        let plan = Plan(name: "swap", fixed: [:], slots: [slot], overlayerTop: layered, setFamily: false)
        let cands: [EngineItem] = isAcc ? accessories : slotPool(slot, plan)
        let taken = Set(outfit.slots.values)
        let chosen: Chosen = outfit.slots.compactMapValues { byId[$0] }.filter { !isAcc || $0.key != slot }
        var out: [OutfitCandidate] = []
        for c in cands where !taken.contains(c.id) {
            var trial = chosen; trial[slot] = c
            guard ok(trial, final: true) else { continue }
            var slots = outfit.slots; slots[slot] = c.id
            let (total, parts) = score(trial)
            let cand = OutfitCandidate(slots: slots, score: total, scoreParts: parts)
            if !ctx.excludeOutfits.contains(cand.key) { out.append(cand) }
        }
        out.sort { $0.score != $1.score ? $0.score > $1.score : $0.key.ids.map(\.uuidString).lexicographicallyPrecedes($1.key.ids.map(\.uuidString)) }
        return Array(out.prefix(limit))
    }
}

// MARK: - Debug output

private let partOrder = ["occasionFit", "colourHarmony", "formalityMatch", "pairWeight", "freshness", "variety"]

public extension OutfitCandidate {
    /// Item names in slot order, e.g. "Rust shirt + Black chinos + Sneakers".
    func describe(items: [EngineItem]) -> String {
        slots.sorted { $0.key < $1.key }.map { s, id in items.first { $0.id == id }?.name ?? id.uuidString }.joined(separator: " + ")
    }
    var scoreText: String { String(format: "%.3f", score) }
    var partsText: String { partOrder.compactMap { k in scoreParts[k].map { String(format: "%@ %.2f", k, $0) } }.joined(separator: ", ") }
}

public extension EngineResult {
    /// Each outfit with its score parts, then every rejected item with its reason, then missing slots.
    func debugDescription(items: [EngineItem]) -> String {
        func name(_ id: UUID) -> String { items.first { $0.id == id }?.name ?? id.uuidString }
        var out: [String] = []
        for (n, o) in outfits.enumerated() {
            out.append("#\(n + 1) \(o.scoreText)  \(o.describe(items: items))\n     \(o.partsText)")
        }
        if outfits.isEmpty { out.append("no outfits; missing: \(missing.map(\.rawValue).joined(separator: ", "))") }
        let byReason = Dictionary(grouping: rejected.sorted { name($0.key) < name($1.key) }, by: { $0.value })
        out.append("rejected \(rejected.count), kept \(kept.count)")
        for r in RejectReason.allCases { if let g = byReason[r] {
            out.append("  \(r.rawValue) (\(g.count)): " + g.map { name($0.key) }.joined(separator: "; "))
        } }
        return out.joined(separator: "\n")
    }
}
