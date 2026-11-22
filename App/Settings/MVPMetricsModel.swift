import Foundation
import StyleEngine
import SwiftData
import SwiftUI

/// Bridges the store to the package's metrics (Sprint 6). Tag accuracy per field stays in `AccuracyModel`.
enum MVPMetricsModel {
    static func report(in c: ModelContext, today: Date = .now) -> MVPReport {
        let items = ((try? c.fetch(FetchDescriptor<Item>())) ?? []).filter { $0.status != .archived }.map {
            MVPItem(aiRaw: $0.aiRaw, overrides: $0.userOverrides, createdAt: $0.createdAt, readyAt: $0.readyAt, cutoutFailed: $0.cutoutFailed)
        }
        let logs = ((try? c.fetch(FetchDescriptor<AIRequestLog>())) ?? []).map {
            MVPLog(purpose: $0.purpose, provider: $0.provider, seconds: $0.durationSeconds, success: $0.success, at: $0.createdAt)
        }
        let feedback = ((try? c.fetch(FetchDescriptor<FeedbackEvent>())) ?? []).map(\.action)
        return MVPMetrics.compute(items: items, logs: logs, feedback: feedback, today: today)
    }

    /// Everything for `docs/EVAL_MVP.md` that the app can measure: the metric table plus the tag accuracy table.
    static func markdown(in c: ModelContext) -> String {
        let date = Date.now.formatted(.iso8601.year().month().day())
        let items = (try? c.fetch(FetchDescriptor<Item>())) ?? []
        return MVPMetrics.markdown(report(in: c), date: date) + "\n" + AccuracyModel.markdown(for: items)
    }

    static func exportFile(in c: ModelContext) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("AIStylist-mvp-metrics-\(Date.now.formatted(.iso8601.year().month().day())).md")
        try markdown(in: c).write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}

/// Settings > MVP metrics: the numbers, to read here or send as a file and paste into `docs/EVAL_MVP.md`.
struct MVPMetricsView: View {
    @Environment(\.modelContext) private var context
    @State private var copied = false
    var body: some View {
        let md = MVPMetricsModel.markdown(in: context)
        ScrollView { Text(md).font(.system(.footnote, design: .monospaced)).textSelection(.enabled).padding(16).frame(maxWidth: .infinity, alignment: .leading) }
            .navigationTitle("MVP metrics").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    if let f = try? MVPMetricsModel.exportFile(in: context) { ShareLink(item: f) { Image(systemName: "square.and.arrow.up") } }
                    Button { UIPasteboard.general.string = md; copied = true } label: { Image(systemName: copied ? "checkmark" : "doc.on.doc") }
                }
            }
    }
}
