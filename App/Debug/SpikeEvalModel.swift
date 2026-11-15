import SwiftUI
import StyleEngine

struct SpikePhoto: Identifiable { let id: String; let url: URL }

struct SpikeRow: Identifiable {
    let id: String
    var cutoutSeconds: Double?
    var tagSeconds: [Double] = []
    var got: EvalTags = [:]
    var error: String?
}

@MainActor @Observable
final class SpikeEvalModel {
    var photos: [SpikePhoto] = []
    var expected: [String: EvalTags] = [:]
    var loadProblems: [String] = []
    var longSide: CGFloat = 768
    var rows: [SpikeRow] = []
    var running = false
    var progress = ""
    var summary = ""
    var availability = AppleOnDeviceProvider.unavailableReason() ?? "available"

    func load() {
        loadProblems = []
        guard let dir = Bundle.main.url(forResource: "EvalPhotos", withExtension: nil) else {
            loadProblems = ["EvalPhotos folder is not in the app bundle."]; return
        }
        let exts: Set<String> = ["jpg", "jpeg", "png", "heic"]
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        photos = files.filter { exts.contains($0.pathExtension.lowercased()) }
            .map { SpikePhoto(id: $0.deletingPathExtension().lastPathComponent, url: $0) }
            .sorted { $0.id < $1.id }
        do {
            let data = try Data(contentsOf: dir.appending(path: "expected.json"))
            expected = try ExpectedFile.decode(data, allowed: SpikeTaxonomy.allowed)
        } catch {
            expected = [:]
            loadProblems.append("expected.json: \(error)")
        }
        let m = IDMatch(photoIDs: photos.map(\.id), expectedIDs: Array(expected.keys))
        if !m.photosWithoutExpected.isEmpty { loadProblems.append("Photos without expected entry: \(m.photosWithoutExpected.joined(separator: ", "))") }
        if !m.expectedWithoutPhoto.isEmpty { loadProblems.append("Expected entries without photo: \(m.expectedWithoutPhoto.joined(separator: ", "))") }
    }

    func run() async {
        guard !running else { return }
        availability = AppleOnDeviceProvider.unavailableReason() ?? "available"
        guard availability == "available" else { summary = "Model unavailable: \(availability)"; print(summary); return }
        running = true; defer { running = false }
        let previous = Dictionary(uniqueKeysWithValues: rows.map { ($0.id, $0.got) })
        let tagger = SpikeTagger(longSide: longSide)
        var out: [SpikeRow] = []
        for (i, photo) in photos.enumerated() {
            progress = "\(i + 1)/\(photos.count) \(photo.id)"
            out.append(await process(photo, tagger))
            rows = out
        }
        progress = "done"
        summary = Self.summarize(rows: out, expected: expected, longSide: longSide, previous: previous)
        print(summary)
    }

    private func process(_ photo: SpikePhoto, _ tagger: SpikeTagger) async -> SpikeRow {
        var row = SpikeRow(id: photo.id)
        guard let ui = UIImage(contentsOfFile: photo.url.path), let cg = SpikeImage.upright(ui, longSide: 1600) else {
            row.error = "cannot read image"; return row
        }
        let clock = ContinuousClock()
        do {
            let t0 = clock.now
            let cut = try await spikeCutout(cg)
            row.cutoutSeconds = (clock.now - t0) / .seconds(1)
            let r = try await tagger.tag(cutout: cut)
            row.tagSeconds = r.seconds; row.got = r.tags
        } catch {
            row.error = "\(error)"
        }
        return row
    }

    static func summarize(rows: [SpikeRow], expected: [String: EvalTags], longSide: CGFloat, previous: [String: EvalTags]) -> String {
        let scored = rows.filter { expected[$0.id] != nil }
        let report = EvalScorer.score(scored.map { .init(id: $0.id, expected: expected[$0.id]!, got: $0.got) })
        let pass = PassMarks.check(report.accuracies)
        var s = "E-TAG at \(Int(longSide)) px, \(scored.count) items\n"
        s += "field | accuracy | pass mark | pass?\n"
        for f in SpikeTaxonomy.scoredFields {
            let mark = PassMarks.eTag[f].map { String(format: "%.0f%%", $0) } ?? "-"
            let verdict = pass.passed.contains(f) ? "yes" : pass.failed.contains(f) ? "NO" : "n/a"
            s += "\(f) | \(report.accuracyText(f)) | \(mark) | \(verdict)\n"
        }
        let totals = rows.filter { !$0.tagSeconds.isEmpty }.map { $0.tagSeconds.reduce(0, +) }
        if let t = TimingSummary(totals) { s += String(format: "\nTagging per item: median %.1fs, worst %.1fs\n", t.median, t.worst) }
        for (i, name) in ["A", "B", "C"].enumerated() {
            if let t = TimingSummary(rows.compactMap { $0.tagSeconds.count > i ? $0.tagSeconds[i] : nil }) {
                s += String(format: "Call %@: median %.1fs, worst %.1fs\n", name, t.median, t.worst)
            }
        }
        if let t = TimingSummary(rows.compactMap(\.cutoutSeconds)) { s += String(format: "Cut-out: median %.1fs, worst %.1fs\n", t.median, t.worst) }
        let failed = rows.filter { $0.error != nil }
        s += "\nFailed items (cut-out or tagging): \(failed.count)\n"
        for r in failed { s += "  \(r.id): \(r.error!)\n" }
        let differing = previous.isEmpty ? nil : rows.filter { r in previous[r.id].map { $0 != r.got } ?? false }.map(\.id)
        if let differing { s += "Determinism vs previous run: \(differing.count) items differ \(differing.joined(separator: ", "))\n" }
        s += "\nWrong answers (id | field | expected | got)\n"
        for w in report.wrong { s += "\(w.id) | \(w.field) | \(w.expected) | \(w.got.map(String.init(describing:)) ?? "nil")\n" }
        return s
    }
}
