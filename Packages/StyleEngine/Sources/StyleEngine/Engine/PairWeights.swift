import Foundation

// Sprint 5: what the app learned from saves, wears, rejections and swaps. Always recomputed from the event history.

public enum LearningEvent: Sendable, Equatable {
    case saved([UUID])                 // a saved outfit (manual ones too)
    case worn([UUID])
    case rejected([UUID])              // shown, then the user asked for another
    case swapped(removed: UUID, added: UUID, others: [UUID])
}

public enum PairWeights {
    public static let start = 0.5
    public static let range: ClosedRange<Double> = 0.1...1.0
    static let saved = 0.10, worn = 0.15, rejected = -0.03, swappedOut = -0.10, swappedIn = 0.05

    /// Pairs not in the result are at `start`. Summed then clamped, so event order never matters.
    public static func compute(_ events: [LearningEvent]) -> [PairKey: Double] {
        var d: [PairKey: Double] = [:]
        func bump(_ ids: [UUID], _ by: Double) {
            let u = Array(Set(ids))
            for i in u.indices { for j in u.indices where j > i { d[PairKey(u[i], u[j]), default: start] += by } }
        }
        func bump(_ x: UUID, with others: [UUID], _ by: Double) {
            for o in Set(others) where o != x { d[PairKey(x, o), default: start] += by }
        }
        for e in events {
            switch e {
            case .saved(let ids): bump(ids, saved)
            case .worn(let ids): bump(ids, worn)
            case .rejected(let ids): bump(ids, rejected)
            case .swapped(let x, let y, let others):
                bump(x, with: others, swappedOut); bump(y, with: others, swappedIn)
            }
        }
        return d.mapValues { min(max($0, range.lowerBound), range.upperBound) }
    }

    public static func value(_ weights: [PairKey: Double], _ a: UUID, _ b: UUID) -> Double { weights[PairKey(a, b)] ?? start }
}
