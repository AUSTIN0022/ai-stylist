import Foundation

// Sprint 6: the PRD success metrics that are not tag accuracy (that is `WardrobeAccuracy`), computed from plain records.

public struct MVPItem: Sendable {
    public var aiRaw: ItemTags, overrides: ItemTags
    public var createdAt: Date
    public var readyAt: Date?
    public var cutoutFailed: Bool
    public init(aiRaw: ItemTags, overrides: ItemTags, createdAt: Date, readyAt: Date?, cutoutFailed: Bool) {
        self.aiRaw = aiRaw; self.overrides = overrides; self.createdAt = createdAt; self.readyAt = readyAt; self.cutoutFailed = cutoutFailed
    }
}

public struct MVPLog: Sendable {
    public var purpose: String, provider: String
    public var seconds: Double
    public var success: Bool
    public var at: Date
    public init(purpose: String, provider: String, seconds: Double, success: Bool, at: Date) {
        self.purpose = purpose; self.provider = provider; self.seconds = seconds; self.success = success; self.at = at
    }
}

public struct MVPReport: Sendable, Equatable {
    public var itemCount = 0
    public var editsPerItemMedian: Double?
    public var timeToAddMedianSeconds: Double?
    public var tagCallMedianSeconds: Double?
    public var cutoutSuccessPercent: Double?
    public var intentMedianSeconds: Double?
    public var providers: [String] = []
    public var paidProviderUsed = false
    public var useDays = 0, currentStreak = 0, longestStreak = 0
    public var saved = 0, rejected = 0, swapped = 0
}

public enum MVPMetrics {
    /// Providers that cost nothing. Anything else in the call log counts as paid.
    public static let freeProviders: Set<String> = ["onDevice"]

    static func median(_ xs: [Double]) -> Double? {
        guard !xs.isEmpty else { return nil }
        let s = xs.sorted(), n = s.count
        return n % 2 == 1 ? s[n / 2] : (s[n / 2 - 1] + s[n / 2]) / 2
    }

    public static func compute(items: [MVPItem], logs: [MVPLog], feedback: [String], today: Date, calendar: Calendar = .current) -> MVPReport {
        var r = MVPReport()
        r.itemCount = items.count
        r.editsPerItemMedian = median(items.map { Double(WardrobeAccuracy.evalTags($0.overrides).count) })
        r.timeToAddMedianSeconds = median(items.compactMap { i in i.readyAt.map { $0.timeIntervalSince(i.createdAt) } })
        r.cutoutSuccessPercent = items.isEmpty ? nil : Double(items.filter { !$0.cutoutFailed }.count) / Double(items.count) * 100
        r.intentMedianSeconds = median(logs.filter { $0.purpose == "intent" && $0.success }.map(\.seconds))
        r.tagCallMedianSeconds = median(logs.filter { $0.purpose.hasPrefix("tag") && $0.success }.map(\.seconds))
        r.providers = Array(Set(logs.map(\.provider))).sorted()
        r.paidProviderUsed = r.providers.contains { !freeProviders.contains($0) }
        r.saved = feedback.filter { $0 == "saved" }.count
        r.rejected = feedback.filter { $0 == "rejected" }.count
        r.swapped = feedback.filter { $0 == "swapped" }.count

        // A day with a stylist request: an intent call (typed) or a note call (every result set, chips included).
        let days = Set(logs.filter { $0.purpose == "intent" || $0.purpose == "note" }.map { calendar.startOfDay(for: $0.at) })
        r.useDays = days.count
        let sorted = days.sorted()
        var run = 0, longest = 0, prev: Date?
        for d in sorted {
            if let p = prev, calendar.date(byAdding: .day, value: 1, to: p) == d { run += 1 } else { run = 1 }
            longest = max(longest, run); prev = d
        }
        r.longestStreak = longest
        // Current streak: counting back from today, or from yesterday while today has no request yet.
        let t = calendar.startOfDay(for: today)
        var cursor = days.contains(t) ? t : calendar.date(byAdding: .day, value: -1, to: t)!
        var cur = 0
        while days.contains(cursor) { cur += 1; cursor = calendar.date(byAdding: .day, value: -1, to: cursor)! }
        r.currentStreak = cur
        return r
    }

    public static func markdown(_ r: MVPReport, date: String) -> String {
        func n(_ v: Double?, _ unit: String = "", digits: Int = 1) -> String { v.map { String(format: "%.\(digits)f", $0) + unit } ?? "n/a" }
        var out = "## MVP metrics (\(r.itemCount) items, \(date))\n\n| Metric | Value |\n|---|---|\n"
        out += "| Edits per item (median override fields) | \(n(r.editsPerItemMedian, digits: 1)) |\n"
        out += "| Time to add an item (median, created to ready) | \(n(r.timeToAddMedianSeconds, " s")) |\n"
        out += "| Tagging call time (median per call) | \(n(r.tagCallMedianSeconds, " s")) |\n"
        out += "| Cut-out success | \(n(r.cutoutSuccessPercent, "%", digits: 0)) |\n"
        out += "| Intent to results (median intent call; engine time not logged) | \(n(r.intentMedianSeconds, " s")) |\n"
        out += "| Outfit feedback (saved / rejected / swapped) | \(r.saved) / \(r.rejected) / \(r.swapped) |\n"
        out += "| Running cost | \(r.paidProviderUsed ? "PAID provider in the log: " + r.providers.joined(separator: ", ") : "$0 (providers: " + (r.providers.isEmpty ? "none yet" : r.providers.joined(separator: ", ")) + ")") |\n"
        out += "| Personal use (days with a stylist request; current / longest streak) | \(r.useDays) days; \(r.currentStreak) / \(r.longestStreak) |\n"
        return out
    }
}
