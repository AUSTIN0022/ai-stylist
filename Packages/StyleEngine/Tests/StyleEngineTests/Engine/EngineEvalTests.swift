import Foundation
import Testing
@testable import StyleEngine

/// E-ENG: prints the top 3 for the 10 rating occasions (SPRINT_6_TESTS.md) with score parts.
/// `WRITE_EVAL=/path/body.md swift test --filter E-ENG` also writes the markdown tables there (pasted into docs/EVAL_ENGINE.md).
@Suite("E-ENG") struct EngineEvalTests {
    static let rated: [(String, OccasionIntent)] = [
        ("Office, normal day", .init(occasion: .office, weatherFeel: .mild)),
        ("Interview", .init(occasion: .interview, weatherFeel: .mild)),
        ("Date night", .init(occasion: .date, timeOfDay: .evening, weatherFeel: .mild)),
        ("House party", .init(occasion: .party, timeOfDay: .evening, setting: .indoor, weatherFeel: .mild)),
        ("Diwali at a friend's, evening, indoors", .diwali),
        ("Wedding guest", .init(occasion: .weddingGuest, timeOfDay: .evening, weatherFeel: .mild)),
        ("Temple visit", .init(occasion: .puja, weatherFeel: .mild, flags: [.religiousSite])),
        ("Travel day", .init(occasion: .travel, weatherFeel: .mild, flags: [.lotsOfWalking])),
        ("Casual weekend, hot", .init(occasion: .casualDay, weatherFeel: .hot)),
        ("Evening out, cold", .init(occasion: .party, timeOfDay: .evening, weatherFeel: .cold)),
    ]

    static func intentLine(_ i: OccasionIntent) -> String {
        var p = ["\(i.occasion.rawValue)", "\(i.timeOfDay.rawValue)", "\(i.setting.rawValue)", "\(i.weatherFeel.rawValue)"]
        if i.preferIndian { p.append("preferIndian") }
        p += i.flags.map(\.rawValue).sorted()
        return p.joined(separator: ", ")
    }

    @Test("E-ENG every rated occasion yields three outfits; prints and optionally records them") func eval() throws {
        let f = try loadFixture()
        let c = EngineContext(today: Date(timeIntervalSince1970: 1_794_000_000), seed: 20261114)  // 2026-11-07..: fixed so output is reproducible
        var md = ""
        for (n, (title, intent)) in Self.rated.enumerated() {
            let r = OutfitEngine.generate(intent: intent, items: f.items, context: c)
            #expect(r.outfits.count == 3, "\(title)")
            md += "### \(n + 1). \(title)\n\nIntent: `\(Self.intentLine(intent))`\n\n"
            md += "| # | Outfit | Score | Parts | Wear / Wouldn't |\n|---|---|---|---|---|\n"
            for (k, o) in r.outfits.enumerated() {
                md += "| \(k + 1) | \(o.describe(items: f.items)) | \(o.scoreText) | \(o.partsText) | |\n"
            }
            md += "\n"
            print("== \(title) [\(Self.intentLine(intent))]\n\(r.debugDescription(items: f.items))")
        }
        guard let path = ProcessInfo.processInfo.environment["WRITE_EVAL"], !path.isEmpty else { return }
        try md.write(toFile: path, atomically: true, encoding: .utf8)
    }
}
