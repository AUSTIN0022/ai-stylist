import CoreGraphics
import Foundation
import WardrobeImaging

/// Seam over the image feature print so review tests run with made-up prints and distances.
protocol FeaturePrinting: Sendable {
    func compute(from image: CGImage) -> Data?
    func distance(_ a: Data, _ b: Data) -> Double?
}

struct VisionFeaturePrinting: FeaturePrinting {
    func compute(from image: CGImage) -> Data? { FeaturePrint.compute(from: image) }
    func distance(_ a: Data, _ b: Data) -> Double? { FeaturePrint.distance(a, b) }
}

/// "Is this the same as <name>?" shown on a review page.
struct DuplicateOffer: Equatable { let itemID: UUID; let name: String; let distance: Double }
