import Foundation
import Testing
@testable import StyleEngine

// S6-I04: the MVP metrics on a seeded set with known overrides and timings.

private var utc: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c }
private func day(_ d: Int, hour: Int = 10) -> Date {
    utc.date(from: DateComponents(timeZone: TimeZone(identifier: "UTC"), year: 2026, month: 12, day: d, hour: hour))!
}
private func item(edits: Int = 0, ready: TimeInterval? = 20, failed: Bool = false) -> MVPItem {
    var raw = ItemTags(); raw.category = .top; raw.subcategory = .shirt; raw.fabric = .cotton; raw.pattern = .solid
    var o = ItemTags()
    if edits > 0 { o.fabric = .linen }
    if edits > 1 { o.pattern = .stripe }
    if edits > 2 { o.fit = .slim }
    return MVPItem(aiRaw: raw, overrides: o, createdAt: day(1), readyAt: ready.map { day(1).addingTimeInterval($0) }, cutoutFailed: failed)
}
private func log(_ purpose: String, _ secs: Double = 2, _ d: Int = 1, provider: String = "onDevice", ok: Bool = true) -> MVPLog {
    MVPLog(purpose: purpose, provider: provider, seconds: secs, success: ok, at: day(d))
}

@Suite("S6 MVP metrics") struct MVPMetricsTests {
    func report(items: [MVPItem] = [], logs: [MVPLog] = [], feedback: [String] = [], today: Int = 5) -> MVPReport {
        MVPMetrics.compute(items: items, logs: logs, feedback: feedback, today: day(today), calendar: utc)
    }

    @Test("edits per item: median count of override fields") func edits() {
        #expect(report(items: [item(edits: 0), item(edits: 1), item(edits: 3)]).editsPerItemMedian == 1)
        #expect(report(items: [item(edits: 0), item(edits: 2)]).editsPerItemMedian == 1)     // even count: mean of the middle two
        #expect(report().editsPerItemMedian == nil)
    }

    @Test("time to add: median of ready minus created; items not ready are left out") func timeToAdd() {
        let r = report(items: [item(ready: 10), item(ready: 30), item(ready: 20), item(ready: nil)])
        #expect(r.timeToAddMedianSeconds == 20)
    }

    @Test("cut-out success is the share without a failure") func cutout() {
        #expect(report(items: [item(), item(), item(), item(failed: true)]).cutoutSuccessPercent == 75)
    }

    @Test("intent to results: median of successful intent calls") func intent() {
        let r = report(logs: [log("intent", 2), log("intent", 4), log("intent", 3), log("intent", 99, ok: false), log("tagA", 50)])
        #expect(r.intentMedianSeconds == 3)
    }

    @Test("tagging time: median per tagging call") func tagging() {
        let r = report(logs: [log("tagA", 2), log("tagB", 4), log("tagC", 6), log("note", 100)])
        #expect(r.tagCallMedianSeconds == 4)
    }

    @Test("running cost: only the on-device provider means no paid provider") func cost() {
        #expect(report(logs: [log("tagA"), log("note")]).paidProviderUsed == false)
        let paid = report(logs: [log("tagA"), log("tagA", provider: "gemini")])
        #expect(paid.paidProviderUsed && paid.providers == ["gemini", "onDevice"])
        #expect(report().paidProviderUsed == false)
    }

    @Test("personal use: days with a stylist request, current and longest streak") func usage() {
        // Requests (intent or note calls) on 1, 2, 4, 5. Today is the 5th: current streak 2 (4,5), longest 2.
        let r = report(logs: [log("intent", 1, 1), log("note", 1, 2), log("intent", 1, 4), log("note", 1, 5), log("tagA", 1, 3)])
        #expect(r.useDays == 4 && r.currentStreak == 2 && r.longestStreak == 2)
        // Nothing today or yesterday: current streak 0.
        #expect(report(logs: [log("intent", 1, 1)], today: 5).currentStreak == 0)
        // Yesterday counts: the streak is still alive until today ends.
        #expect(report(logs: [log("intent", 1, 3), log("intent", 1, 4)], today: 5).currentStreak == 2)
    }

    @Test("outfit feedback counts") func feedback() {
        let r = report(feedback: ["saved", "saved", "rejected", "swapped", "other"])
        #expect(r.saved == 2 && r.rejected == 1 && r.swapped == 1)
    }

    @Test("markdown has one row per metric") func markdown() {
        let md = MVPMetrics.markdown(report(items: [item(edits: 1)], logs: [log("intent")]), date: "2026-12-01")
        for key in ["Edits per item", "Time to add", "Cut-out success", "Intent to results", "Running cost", "Personal use", "Outfit feedback"] {
            #expect(md.contains(key), "\(key)")
        }
    }
}
