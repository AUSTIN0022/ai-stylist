import CoreGraphics
import Foundation
import FoundationModels
import StyleEngine
import os

/// Apple adapter for `ItemTagger`: calls A, B and C on the on-device model: each a fresh session, greedy, cut-out on white at 768 px (same shape as the
/// Sprint 0 spike). Call B's struct depends on the category from call A (`constructionFields(for:)`).
/// Bump `version` when a prompt or a struct changes, then re-run E-TAG.
final class FoundationModelsTagger: ItemTagger, TokenReporting, AvailabilityReporting, ProviderReporting {
    let providerName = AppleOnDeviceProvider.name
    let version = "fm-ondevice-2"
    private let tokens = OSAllocatedUnfairLock<Int?>(initialState: nil)
    var lastTokenCount: Int? { tokens.withLock { $0 } }
    var unavailableReason: String? { AppleOnDeviceProvider.unavailableReason() }

    func identity(cutout: CGImage) async throws -> IdentityTags {
        try await call(IdentityTags.self, cutout, "You label one clothing item in a photo. Choose only from the allowed values.",
                       "Label the kind of clothing item in this image.")
    }

    func construction(cutout: CGImage, category: StyleEngine.Category, subcategory: Subcategory) async throws -> ItemTags {
        let ins = "You describe how one clothing item is made. Choose only from the allowed values."
        let what = subcategory.displayName.lowercased()
        switch category {
        case .top, .outerwear, .onePiece:
            return try await call(TopConstruction.self, cutout, ins, "Describe the fabric, pattern, fit, length, collar and sleeve of this \(what).").tags
        case .bottom:
            return try await call(BottomConstruction.self, cutout, ins, "Describe the fabric, pattern, fit and length of these \(what).").tags
        case .footwear:
            return try await call(FootwearConstruction.self, cutout, ins, "Describe the material of these \(what) and whether the toes are covered.").tags
        case .accessory:
            return try await call(AccessoryConstruction.self, cutout, ins, "Describe the material of this \(what).").tags
        }
    }

    func usage(cutout: CGImage, category: StyleEngine.Category, subcategory: Subcategory) async throws -> ItemTags {
        try await call(UsageTags.self, cutout, "You decide when a clothing item is worn. Choose only from the allowed values.",
                       "When would someone wear this \(subcategory.displayName.lowercased())? Describe only the garment in the caption.").tags
    }

    private func call<T: Generable>(_ type: T.Type, _ cutout: CGImage, _ instructions: String, _ prompt: String) async throws -> T {
        if let reason = unavailableReason { throw AIUnavailable(reason: reason) }
        guard let img = SpikeImage.onWhite(cutout, longSide: 768) else { throw SpikeCutoutError.render }
        tokens.withLock { $0 = nil }
        let session = LanguageModelSession(instructions: instructions)   // fresh context every call
        let response = try await session.respond(generating: T.self, options: GenerationOptions(samplingMode: .greedy)) {
            prompt
            Attachment(img)
        }
        let total = response.usage.totalTokenCount
        tokens.withLock { $0 = total }
        return response.content
    }
}
