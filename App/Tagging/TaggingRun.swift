import CoreGraphics
import StyleEngine

/// Calls A, B, C in order (B depends on A's category), one logged call each. Used by the review (live) and the queue.
enum TaggingRun {
    /// Throws on the first failing call; calls before it have already been logged. `onIdentity` fires as soon as A answers.
    static func run(tagger: any ItemTagger, cutout: CGImage, sink: @escaping @Sendable (AICallRecord) async -> Void,
                    onIdentity: @Sendable (IdentityTags) async -> Void = { _ in }) async throws -> ItemTags {
        let tokens: @Sendable () -> Int? = { (tagger as? TokenReporting)?.lastTokenCount }
        let a = try await AICall.record(purpose: "tagA", model: tagger.version, tokens: tokens, sink: sink) { try await tagger.identity(cutout: cutout) }
        await onIdentity(a)
        let b = try await AICall.record(purpose: "tagB", model: tagger.version, tokens: tokens, sink: sink) {
            try await tagger.construction(cutout: cutout, category: a.category, subcategory: a.subcategory)
        }
        let c = try await AICall.record(purpose: "tagC", model: tagger.version, tokens: tokens, sink: sink) {
            try await tagger.usage(cutout: cutout, category: a.category, subcategory: a.subcategory)
        }
        return a.tags.overlaid(with: construction(for: a.category, in: b)).overlaid(with: c)
    }
}
