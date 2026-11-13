import Foundation
import StyleEngine

/// Bridges saved items to the package's accuracy function: only items that have an AI answer count.
enum AccuracyModel {
    static func report(for items: [Item]) -> WardrobeAccuracy.Report {
        WardrobeAccuracy.report(items.filter { $0.aiRawData != nil }.map {
            AccuracySample(id: $0.name.isEmpty ? String($0.id.uuidString.prefix(8)) : $0.name, aiRaw: $0.aiRaw, effective: $0.tags,
                           labelScan: $0.labelScan, label: $0.label)
        })
    }
    static func markdown(for items: [Item]) -> String {
        WardrobeAccuracy.markdown(report(for: items), date: Date.now.formatted(.iso8601.year().month().day()))
    }

    /// The table as a named .md file in the temporary folder: WhatsApp and AirDrop take a file reliably, a bare String not always.
    static func exportFile(for items: [Item]) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("AIStylist-accuracy-\(Date.now.formatted(.iso8601.year().month().day())).md")
        try markdown(for: items).write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}
