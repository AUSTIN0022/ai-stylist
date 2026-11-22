import Foundation

public enum Rating: String, Codable, Sendable { case wear, wouldNot }

/// The E-ENG rating sheet (SPRINT_6_TESTS.md): the ten requests, the scoring rule, and the markdown for `docs/EVAL_MVP.md`.
public enum RatingSheet {
    public static let requests: [(title: String, intent: OccasionIntent)] = [
        ("Office, normal day", .init(occasion: .office, weatherFeel: .mild)),
        ("Interview", .init(occasion: .interview, weatherFeel: .mild)),
        ("Date night", .init(occasion: .date, timeOfDay: .evening, weatherFeel: .mild)),
        ("House party", .init(occasion: .party, timeOfDay: .evening, setting: .indoor, weatherFeel: .mild)),
        ("Diwali at a friend's, evening, indoors", .init(occasion: .festival, timeOfDay: .evening, setting: .indoor, weatherFeel: .mild)),
        ("Wedding guest", .init(occasion: .weddingGuest, timeOfDay: .evening, weatherFeel: .mild)),
        ("Temple visit", .init(occasion: .puja, weatherFeel: .mild, flags: [.religiousSite])),
        ("Travel day", .init(occasion: .travel, weatherFeel: .mild, flags: [.lotsOfWalking])),
        ("Casual weekend, hot", .init(occasion: .casualDay, weatherFeel: .hot)),
        ("Evening out, cold", .init(occasion: .party, timeOfDay: .evening, weatherFeel: .cold)),
    ]

    /// Fixed so a "before" and an "after tuning" round show the same variety term and differ only by what was tuned.
    public static let context = EngineContext(today: Date(timeIntervalSince1970: 1_794_000_000), seed: 20261114)

    public struct Entry: Sendable, Equatable, Codable {
        public var description: String
        public var rating: Rating?
        public var reason: String
        public init(description: String, rating: Rating? = nil, reason: String = "") {
            self.description = description; self.rating = rating; self.reason = reason
        }
    }

    public struct Row: Sendable, Equatable, Codable {
        public var title: String
        public var outfits: [Entry]
        public init(title: String, outfits: [Entry]) { self.title = title; self.outfits = outfits }
        public var wearable: Int { outfits.filter { $0.rating == .wear }.count }
        public var isComplete: Bool { !outfits.isEmpty && outfits.allSatisfy { $0.rating != nil } }
        /// At least 2 of the top 3 wearable.
        public var passes: Bool { wearable >= 2 }
    }

    public static func passed(_ rows: [Row]) -> Int { rows.filter(\.passes).count }

    /// Where a "wouldn't wear" reason is fixed (SPRINT_6.md step 3). Keyword match, case-insensitive.
    public static func group(for reason: String) -> String {
        let r = reason.lowercased()
        func has(_ words: String...) -> Bool { words.contains { r.contains($0) } }
        if has("tag") { return "Not the engine: fix the tag" }
        if has("clash") { return "Colour table clash list" }
        if has("shoe", "footwear") { return "Footwear rules and formalityMatch weight" }
        if has("formal", "casual") { return "Occasion table: formality range" }
        if has("plain", "dark", "boring", "dull") { return "Colour table" }
        if has("same", "repeat", "always") { return "Diversity: variety and freshness weights" }
        return "Other"
    }

    public static func markdown(_ rows: [Row], round: String, date: String) -> String {
        var out = "### E-ENG rating sheet: \(round) (\(date))\n\n| # | Request | Outfit 1 | Outfit 2 | Outfit 3 | Wearable | Pass (≥ 2) |\n|---|---|---|---|---|---|---|\n"
        func cell(_ e: Entry?) -> String {
            guard let e else { return "" }
            switch e.rating {
            case .wear: return "W"
            case .wouldNot: return e.reason.isEmpty ? "N" : "N (\(e.reason))"
            case nil: return "·"
            }
        }
        for (n, r) in rows.enumerated() {
            let cells = (0..<3).map { cell(r.outfits.indices.contains($0) ? r.outfits[$0] : nil) }
            out += "| \(n + 1) | \(r.title) | \(cells.joined(separator: " | ")) | \(r.wearable)/\(max(r.outfits.count, 3)) | \(r.passes ? "✅" : "❌") |\n"
        }
        out += "\n\(passed(rows)) of \(rows.count) occasions pass.\n"
        let nos = rows.flatMap { $0.outfits }.filter { $0.rating == .wouldNot }
        if !nos.isEmpty {
            let groups = Dictionary(grouping: nos) { group(for: $0.reason) }
            out += "\nReasons for \"wouldn't wear\", by where the fix goes:\n\n"
            for (g, es) in groups.sorted(by: { $0.value.count > $1.value.count }) {
                out += "- **\(g)** (\(es.count)): " + es.map { "\($0.description)\($0.reason.isEmpty ? "" : " — \($0.reason)")" }.joined(separator: "; ") + "\n"
            }
        }
        return out
    }
}
