import Foundation

// Sprint 4: the shown outfits, the keys already shown, and the exhausted state. No AI; every call is the engine.

public struct ShownOutfit: Identifiable, Equatable, Sendable {
    public let id: UUID
    public var candidate: OutfitCandidate
}

public struct StylistSession: Sendable {
    public enum State: Equatable, Sendable { case idle, showing, exhausted(missing: [Slot]) }
    public private(set) var state: State = .idle
    public private(set) var outfits: [ShownOutfit] = []
    /// Every key ever shown this session (including swapped versions): the engine's exclusion set.
    public private(set) var shown: Set<OutfitKey> = []
    /// Looks shown so far (twin items look the same): Another option never repeats one.
    public private(set) var shownLooks: Set<[String]> = []
    /// Slots the shown outfits are built without (footwear): the screen says what to add.
    public private(set) var softMissing: [Slot] = []
    public init() {}

    private func context(_ today: Date, _ seed: UInt64) -> EngineContext {
        EngineContext(today: today, excludeOutfits: shown, seed: seed, excludeLooks: shownLooks)
    }

    /// New request or edited chip: forget what was shown and build three outfits.
    public mutating func start(intent: OccasionIntent, items: [EngineItem], today: Date = Date(), seed: UInt64 = 0) {
        shown = []; shownLooks = []; outfits = []; state = .idle; softMissing = []
        _ = another(intent: intent, items: items, today: today, seed: seed)
    }

    /// Three new outfits that were never shown. Returns the ones replaced (empty when nothing new exists:
    /// the old outfits stay and the state becomes `exhausted` with the engine's missing slots).
    @discardableResult
    public mutating func another(intent: OccasionIntent, items: [EngineItem], today: Date = Date(), seed: UInt64 = 0) -> [ShownOutfit] {
        let r = OutfitEngine.generate(intent: intent, items: items, context: context(today, seed))
        guard !r.outfits.isEmpty else { state = .exhausted(missing: r.missing); return [] }
        let old = outfits
        outfits = r.outfits.map { ShownOutfit(id: UUID(), candidate: $0) }
        shown.formUnion(r.outfits.map(\.key))
        shownLooks.formUnion(r.outfits.map { OutfitEngine.look(of: $0, items: items) })
        softMissing = r.softMissing
        state = .showing
        return old
    }

    /// Other items for one slot of a shown outfit, best first, never an outfit already shown.
    public func alternatives(for outfit: UUID, slot: Slot, intent: OccasionIntent, items: [EngineItem],
                             today: Date = Date(), seed: UInt64 = 0, limit: Int = 5) -> [OutfitCandidate] {
        guard let o = outfits.first(where: { $0.id == outfit }) else { return [] }
        return OutfitEngine.alternatives(for: slot, in: o.candidate, intent: intent, items: items, context: context(today, seed), limit: limit)
    }

    /// Replaces one item; every other slot stays.
    public mutating func swap(_ outfit: UUID, slot: Slot, to item: UUID) {
        guard let n = outfits.firstIndex(where: { $0.id == outfit }) else { return }
        var slots = outfits[n].candidate.slots; slots[slot] = item
        let old = outfits[n].candidate
        outfits[n].candidate = OutfitCandidate(slots: slots, score: old.score, scoreParts: old.scoreParts)
        shown.insert(outfits[n].candidate.key)
    }
}
