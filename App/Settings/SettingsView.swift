import ImagePlayground
import StyleEngine
import SwiftData
import SwiftUI
import UniformTypeIdentifiers
import WardrobeImaging

/// Settings: AI status, counts, Accuracy, AI log, Developer, Delete all data. Has its own NavigationStack, so present it as a sheet.
struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Item.createdAt) private var items: [Item]
    @Query private var logs: [AIRequestLog]
    private let env: AppEnvironment
    @State private var status: AIStatus.Info
    @State private var showDeveloper = false
    @AppStorage(ProductPromptStyle.key) private var promptStyle = ProductPromptStyle.proven.rawValue
    @State private var confirmDelete = false
    @State private var message: String?
    @State private var refreshing = false
    @State private var shot = ProductShotSession()
    @State private var batchRunning = false
    @State private var tick = 0
    @State private var showImporter = false
    @Environment(\.supportsImagePlayground) private var supportsImagePlayground

    init(env: AppEnvironment) { self.env = env; _status = State(initialValue: AIStatus.current(env.provider)) }

    /// Rebuilds every item's display image in the catalogue look from its stored cut-out; originals and cut-outs are untouched.
    private func refreshCatalogue() {
        refreshing = true
        let jobs = items.map { ($0.id, $0.tags.category) }   // product photos already use the catalogue canvas: skipped below
        let store = env.store
        Task.detached(priority: .userInitiated) {
            let processor = ItemImageProcessor(cutout: VisionCutoutService(), store: store)
            var failed = 0
            for (id, category) in jobs where !FileManager.default.fileExists(atPath: store.url(for: ImageStore.productName, id: id).path) { do { try processor.refreshDisplay(for: id, category: category) } catch { failed += 1 } }
            await MainActor.run {
                refreshing = false
                message = failed == 0 ? "Updated \(jobs.count) images." : "Updated \(jobs.count - failed), \(failed) had no cut-out."
                NotificationCenter.default.post(name: .itemImagesChanged, object: nil)
            }
        }
    }

    private var withoutProduct: [Item] { _ = tick; return items.filter { !ProductShotSession.hasProduct($0, store: env.store) } }

    /// One sheet per item, the user taps Use or Cancel each time. Cancel ends the run (the rest are offered again next time).
    private func makeProductPhotos() {
        batchRunning = true; shot.context = context
        let queue = withoutProduct
        Task {
            for it in queue {
                let o = await shot.make(for: it)
                tick += 1
                if o == .cancelled { message = "Stopped. \(withoutProduct.count) left."; break }
                if case .failed(let e) = o { message = e; break }
            }
            batchRunning = false
        }
    }

    private var stats: SettingsStats { _ = items.count; _ = logs.count; return SettingsStats.compute(in: context) }
    private var exportFile: URL? { _ = items.count; return try? WardrobeExport.file(from: context) }

    private func count(_ s: ItemStatus) -> Int { items.filter { $0.status == s }.count }
    private var untagged: Int { items.filter { $0.status == .ready && $0.aiRawData == nil }.count }
    private var reviewed: Int { items.filter { $0.aiRawData != nil }.count }

    var body: some View {
        NavigationStack {
            List {
                Section("AI") {
                    Label(status.banner == nil ? "On-device model ready" : "Off", systemImage: status.banner == nil ? "checkmark.circle" : "exclamationmark.triangle")
                    if let b = status.banner { Text(b).font(.footnote).foregroundStyle(.secondary) }
                    Text("Tagger \(env.provider.makeTagger().version)").font(.footnote).foregroundStyle(.secondary)
                    if status.manualMode == false, untagged > 0 {
                        Button("Tag \(untagged) untagged item\(untagged == 1 ? "" : "s")") { Task { _ = await env.tagging.tagUntagged() } }
                    }
                    if count(.failed) > 0 {
                        Button("Try again on \(count(.failed)) failed item\(count(.failed) == 1 ? "" : "s")") {
                            let ids = items.filter { $0.status == .failed }.map(\.id)
                            Task { for id in ids { await env.tagging.retry(id) } }
                        }
                    }
                    Button("Check again") { status = AIStatus.current(env.provider) }
                }
                Section("Wardrobe") {
                    LabeledContent("Items", value: "\(items.count)")
                    LabeledContent("Tagged by AI", value: "\(reviewed)")
                    LabeledContent("Tagging now", value: "\(count(.tagging))")
                    LabeledContent("Failed", value: "\(count(.failed))")
                    LabeledContent("AI calls logged", value: "\(logs.count)")
                    LabeledContent("AI calls this week", value: "\(stats.aiCallsThisWeek)")
                    LabeledContent("Median tagging time", value: stats.medianTaggingSeconds.map { String(format: "%.1f s", $0) } ?? "n/a")
                    LabeledContent("Outfits", value: "\(stats.outfits)")
                    Button(refreshing ? "Refreshing catalogue images…" : "Refresh catalogue images") { refreshCatalogue() }
                        .disabled(refreshing || items.isEmpty)
                    if supportsImagePlayground {
                        Button("Make product photos (\(withoutProduct.count))") { makeProductPhotos() }
                            .disabled(batchRunning || withoutProduct.isEmpty)
                    } else {
                        Text(productShotUnavailableReason).font(.footnote).foregroundStyle(.secondary)
                    }
                }
                Section("Backup") {
                    if let f = exportFile { ShareLink(item: f) { Label("Export wardrobe (JSON)", systemImage: "square.and.arrow.up") } }
                    #if DEBUG
                    Button("Import wardrobe.json (debug)") { showImporter = true }
                    #endif
                }
                Section {
                    NavigationLink("Accuracy") { AccuracyView() }
                    NavigationLink("AI log") { AILogView() }
                }
                Section("Developer") {
                    Picker("Product photo prompt", selection: $promptStyle) {
                        ForEach(ProductPromptStyle.allCases) { Text($0.label).tag($0.rawValue) }
                    }
                    NavigationLink("Templates") { TemplatesView() }
                    Button("Photo eval (bundled photos)") { showDeveloper = true }
                }
                Section {
                    Button("Delete all data", role: .destructive) { confirmDelete = true }
                    if let m = message { Text(m).font(.footnote).foregroundStyle(.secondary) }
                }
            }
            .productShotSheet(shot)
            .fileImporter(isPresented: $showImporter, allowedContentTypes: [.json]) { r in
                guard case .success(let url) = r, url.startAccessingSecurityScopedResource() else { return }
                defer { url.stopAccessingSecurityScopedResource() }
                message = (try? Data(contentsOf: url)).flatMap { try? WardrobeExport.importData($0, into: context) }.map { "Imported \($0) items." } ?? "Import failed."
            }
            .onReceive(NotificationCenter.default.publisher(for: .itemImagesChanged)) { _ in tick += 1 }
            .navigationTitle("Settings").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .fullScreenCover(isPresented: $showDeveloper) {
                DebugEvalView().overlay(alignment: .topLeading) { Button("Close") { showDeveloper = false }.buttonStyle(.bordered).padding() }
            }
            .confirmationDialog("Delete \(DataReset.counts(in: context).summary) and all photos? This cannot be undone.",
                                isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete everything", role: .destructive) {
                    DataReset.deleteAll(in: context, store: env.store)
                    message = "All data deleted."
                }
            }
        }
    }
}

/// The last 100 AI calls, newest first.
struct AILogView: View {
    @Query(sort: \AIRequestLog.createdAt, order: .reverse) private var all: [AIRequestLog]
    var body: some View {
        List(all.prefix(100), id: \.persistentModelID) { r in
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(r.purpose).font(.body.monospaced())
                    Image(systemName: r.success ? "checkmark.circle" : "xmark.circle").foregroundStyle(r.success ? .green : .red)
                    Spacer()
                    Text(String(format: "%.1f s", r.durationSeconds)).foregroundStyle(.secondary)
                }
                Text("\(r.provider) · \(r.model) · \(r.outputTokens.map { "\($0) tokens" } ?? "tokens n/a") · \(r.createdAt.formatted(date: .abbreviated, time: .standard))")
                    .font(.caption).foregroundStyle(.secondary)
                if let e = r.errorText { Text(e).font(.caption).foregroundStyle(.red) }
                if let d = r.detail { Text(d).font(.caption2).foregroundStyle(.secondary) }
            }
        }
        .overlay { if all.isEmpty { ContentUnavailableView("No AI calls yet", systemImage: "list.bullet") } }
        .navigationTitle("AI log").navigationBarTitleDisplayMode(.inline)
    }
}

/// "Eval from my wardrobe": per-field accuracy of the AI against what you saved, with the TEST_PLAN pass marks.
struct AccuracyView: View {
    @Query private var items: [Item]
    @State private var copied = false
    var body: some View {
        let r = AccuracyModel.report(for: items)
        List {
            if r.itemCount == 0 {
                ContentUnavailableView("Nothing to measure yet", systemImage: "chart.bar",
                                       description: Text("Review and save items that the AI tagged. Fields you change count as AI misses."))
            } else {
                Section("Tags from \(r.itemCount) reviewed items") {
                    ForEach(WardrobeAccuracy.fields, id: \.self) { f in
                        HStack {
                            Text(f)
                            Spacer()
                            Text(r.tag.accuracyText(f)).monospacedDigit()
                            if let m = WardrobeAccuracy.marks[f] {
                                Text("≥ \(Int(m))%").font(.caption).foregroundStyle(.secondary)
                                Image(systemName: r.result.passed.contains(f) ? "checkmark.circle.fill" : r.result.failed.contains(f) ? "xmark.circle.fill" : "minus.circle")
                                    .foregroundStyle(r.result.passed.contains(f) ? .green : r.result.failed.contains(f) ? .red : .secondary)
                            }
                        }
                    }
                }
                Section("Label read (\(r.labelItems) items with a label)") {
                    LabeledContent("Left as scanned", value: r.labelAccuracy.map { String(format: "%.1f%%", $0) } ?? "n/a")
                    ForEach(r.labelFields.keys.sorted(), id: \.self) { f in
                        LabeledContent(f, value: "\(r.labelFields[f]!.right) of \(r.labelFields[f]!.scored)")
                    }
                }
                Section {
                    if let file = try? AccuracyModel.exportFile(for: items) {
                        ShareLink(item: file, preview: SharePreview("AI Stylist accuracy table")) {
                            Label("Share as file (.md)", systemImage: "square.and.arrow.up")
                        }
                    }
                    Button { UIPasteboard.general.string = AccuracyModel.markdown(for: items); copied = true } label: {
                        Label(copied ? "Copied" : "Copy table", systemImage: copied ? "checkmark" : "doc.on.doc")
                    }
                }
            }
        }
        .navigationTitle("Accuracy").navigationBarTitleDisplayMode(.inline)
    }
}
