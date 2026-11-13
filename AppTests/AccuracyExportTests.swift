import Foundation
import Testing
@testable import AIStylist

/// Device report (14 Nov): "Share as EVAL table" did nothing in WhatsApp or AirDrop. A bare String share is unreliable,
/// so the table is exported as a named Markdown file.
@Test func S2_U54_accuracyExportWritesNamedMarkdownFile() throws {
    let url = try AccuracyModel.exportFile(for: [])
    defer { try? FileManager.default.removeItem(at: url) }
    #expect(url.pathExtension == "md")
    #expect(url.lastPathComponent.hasPrefix("AIStylist-accuracy-"))
    let text = try String(contentsOf: url, encoding: .utf8)
    #expect(!text.isEmpty)
    #expect(text == AccuracyModel.markdown(for: []))
}
