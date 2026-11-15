import Foundation
import FoundationModels
import StyleEngine
import os

@Generable struct GeneratedNotes {
    @Guide(description: "One or two sentences on why outfit 1 suits the occasion")
    var outfit1: String
    @Guide(description: "One or two sentences on why outfit 2 suits the occasion")
    var outfit2: String
    @Guide(description: "One or two sentences on why outfit 3 suits the occasion")
    var outfit3: String
}

/// Apple adapter for `NoteWriter`: one on-device call for all outfit notes.
final class FoundationModelsNoteWriter: NoteWriter, TokenReporting, ProviderReporting, @unchecked Sendable {
    let providerName = AppleOnDeviceProvider.name
    let version = "fm-note-1"
    private let tokens = OSAllocatedUnfairLock<Int?>(initialState: nil)
    var lastTokenCount: Int? { tokens.withLock { $0 } }

    static let instructions = """
        For each outfit write one or two sentences on why it suits the occasion. \
        Mention only the listed items. Do not suggest other items.
        """

    func notes(prompt: String, count: Int) async throws -> [String] {
        if let reason = AppleOnDeviceProvider.unavailableReason() { throw AIUnavailable(reason: reason) }
        tokens.withLock { $0 = nil }
        let session = LanguageModelSession(instructions: Self.instructions)
        let r = try await session.respond(to: prompt, generating: GeneratedNotes.self, options: GenerationOptions(samplingMode: .greedy))
        let total = r.usage.totalTokenCount
        tokens.withLock { $0 = total }
        return Array([r.content.outfit1, r.content.outfit2, r.content.outfit3].prefix(count))
    }
}
