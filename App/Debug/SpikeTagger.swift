import Foundation
import CoreGraphics
import FoundationModels
import StyleEngine

struct SpikeTagResult {
    var tags: EvalTags
    /// Seconds for calls A, B, C.
    var seconds: [Double]
    /// Total tokens for calls A, B, C.
    var tokens: [Int]
    var total: Double { seconds.reduce(0, +) }
}

struct SpikeTagger {
    /// Long side of the image sent to the model, in pixels.
    var longSide: CGFloat = 768

    /// nil when the model is usable, else a printable reason.
    static func unavailableReason() -> String? {
        switch SystemLanguageModel.default.availability {
        case .available: nil
        case .unavailable(.deviceNotEligible): "Device not eligible for Apple Intelligence."
        case .unavailable(.appleIntelligenceNotEnabled): "Apple Intelligence is turned off in Settings."
        case .unavailable(.modelNotReady): "Model not ready: still downloading. Stay on Wi-Fi and power."
        case .unavailable(let other): "Model unavailable: \(other)"
        }
    }

    /// Runs calls A, B, C, each in a fresh session, greedy. `cutout` is the transparent cut-out.
    func tag(cutout: CGImage) async throws -> SpikeTagResult {
        guard let img = SpikeImage.onWhite(cutout, longSide: longSide) else { throw SpikeCutoutError.render }
        var tags: EvalTags = [:]
        var seconds: [Double] = [], tokens: [Int] = []

        let a: SpikeIdentityTags = try await call("tagA", img, seconds: &seconds, tokens: &tokens,
            "You label one clothing item in a photo. Choose only from the allowed values.",
            "Label the kind of clothing item in this image.")
        tags["category"] = .single(a.category.rawValue)
        tags["subcategory"] = .single(a.subcategory.rawValue)
        tags["styleOrigin"] = .single(a.styleOrigin.rawValue)

        let b: SpikeConstructionTags = try await call("tagB", img, seconds: &seconds, tokens: &tokens,
            "You describe how one clothing item is made. Choose only from the allowed values.",
            "Describe the fabric, pattern, fit, collar and sleeve of this \(a.subcategory.rawValue).")
        tags["fabric"] = .single(b.fabric.rawValue)
        tags["pattern"] = .single(b.pattern.rawValue)
        tags["fit"] = .single(b.fit.rawValue)
        tags["collar"] = .single(b.collar.rawValue)
        tags["sleeve"] = .single(b.sleeve.rawValue)

        let c: SpikeUsageTags = try await call("tagC", img, seconds: &seconds, tokens: &tokens,
            "You decide when a clothing item is worn. Choose only from the allowed values.",
            "When would someone wear this \(a.subcategory.rawValue)?")
        tags["dressCodes"] = .list(c.dressCodes.map(\.rawValue))
        tags["formality"] = .single(String(c.formality))
        tags["seasons"] = .list(c.seasons.map(\.rawValue))
        tags["caption"] = .single(c.caption)

        return SpikeTagResult(tags: tags, seconds: seconds, tokens: tokens)
    }

    private func call<T: Generable>(_ purpose: String, _ image: CGImage, seconds: inout [Double], tokens: inout [Int],
                                    _ instructions: String, _ prompt: String) async throws -> T {
        let session = LanguageModelSession(instructions: instructions)  // fresh context every call
        let clock = ContinuousClock()
        let start = clock.now
        let response = try await session.respond(generating: T.self, options: GenerationOptions(samplingMode: .greedy)) {
            prompt
            Attachment(image)
        }
        let secs = (clock.now - start) / .seconds(1)
        let tok = response.usage.totalTokenCount
        seconds.append(secs); tokens.append(tok)
        // AI call log (CLAUDE.md): purpose, provider, duration, tokens.
        print(String(format: "[AI] %@ onDevice %.2fs tokens=%d", purpose, secs, tok))
        return response.content
    }
}
