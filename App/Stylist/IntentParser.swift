import Foundation
import StyleEngine

/// Free text and recent turns -> a full `OccasionIntent`. Text only: nothing about the wardrobe goes in.
protocol IntentParser: Sendable {
    var version: String { get }
    func parse(message: String, previous: OccasionIntent?, recent: [String]) async throws -> OccasionIntent
}
