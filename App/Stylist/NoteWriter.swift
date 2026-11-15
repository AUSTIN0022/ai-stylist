import Foundation
import StyleEngine

/// One call for all outfits: text in (`NotePrompt.text`), one note per outfit out. The caller validates and logs.
protocol NoteWriter: Sendable {
    var version: String { get }
    func notes(prompt: String, count: Int) async throws -> [String]
}
