import Foundation

// Sprint 6: "Is this the same as <item>?" The decision only; the distance comes from an image feature print (WardrobeImaging).

public struct DuplicateCandidate: Equatable, Sendable {
    public let id: UUID
    public let subcategory: Subcategory?
    public init(id: UUID, subcategory: Subcategory?) { self.id = id; self.subcategory = subcategory }
}

public struct DuplicateMatch: Equatable, Sendable {
    public let id: UUID
    public let distance: Double
}

public enum DuplicateCheck {
    /// Vision feature-print distance below which two photos count as the same garment. A first guess to tune on your own
    /// wardrobe (the same shirt photographed twice should match; two pairs of black chinos should not, or should at least ask).
    public static let threshold = 0.45

    /// The nearest candidate under `threshold`. Only items of the same subcategory are compared (when both are known),
    /// and a candidate with no distance (an older item with no stored print) is skipped.
    public static func match(subcategory: Subcategory?, among candidates: [DuplicateCandidate], distance: (UUID) -> Double?,
                             threshold: Double = DuplicateCheck.threshold) -> DuplicateMatch? {
        candidates
            .filter { c in subcategory == nil || c.subcategory == nil || c.subcategory == subcategory }
            .compactMap { c in distance(c.id).map { DuplicateMatch(id: c.id, distance: $0) } }
            .filter { $0.distance < threshold }
            .min { $0.distance < $1.distance }
    }
}
