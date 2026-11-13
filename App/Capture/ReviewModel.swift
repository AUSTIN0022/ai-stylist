import CoreGraphics
import Foundation
import Observation
import StyleEngine
import SwiftData
import WardrobeImaging

/// Holds processed photos while the user reviews them. Nothing touches SwiftData until `save`;
/// `discard` deletes that photo's files. Plain observable so tests drive it with a fake cut-out provider.
@MainActor @Observable final class ReviewModel: Identifiable {
    nonisolated var id: ObjectIdentifier { ObjectIdentifier(self) }
    enum Status { case processing, ready, failed, saved, discarded }
    struct Photo: Identifiable {
        var id = UUID()
        var status = Status.processing
        var processed: ProcessedImages?
        var overrides = ItemTags()          // fit etc.; saved as userOverridesData, never aiRaw
        var colorAnswer: ColorName?         // replaces the first colour name; hex unchanged
        var colorDone = false, fitDone = false
        var ai: IdentityTags?               // the tagger's answer to call A (AI output; saved to aiRaw, never to overrides)
        var aiMore = ItemTags()             // calls B and C (fabric, pattern, dress codes...); AI output too
        var tagState = TagState.idle
        var aiVersion: String?
        var showAllChoices = false          // "Something else": full category and subcategory lists
        var label: LabelData?               // confirmed; label.jpg already in the item folder
        var labelScan: LabelData?           // the same label as the scanner parsed it, before the user's edits
        var error: String?                  // last re-cut problem
        var existingID: UUID?               // Review again: the saved item this page edits in place (nil for a new photo)
    }
    enum TagState: Equatable { case idle, running, done, failed(String) }
    /// A scanned label waiting for the user to edit and confirm.
    struct LabelDraft: Identifiable { let id: UUID; var data: LabelData; let jpeg: Data }

    private(set) var photos: [Photo] = []
    /// Set by `retake`: the view reopens the camera and calls `replace` for this photo.
    private(set) var retakeID: UUID?
    var labelDraft: LabelDraft?

    private let processor: ItemImageProcessor
    let store: ImageStore
    private let pipeline: LabelPipeline
    private let tagger: (any ItemTagger)?
    private let queue: TaggingQueue?
    private var tasks: [Task<Void, Never>] = []
    private var liveTagging: [UUID: Task<Void, Never>] = [:]
    /// Where AI call rows are written. Rows made before it is set are kept and written when it arrives.
    var logContext: ModelContext? { didSet { flushLogs() } }
    private var pendingLogs: [AIRequestLog] = []

    init(processor: ItemImageProcessor, store: ImageStore, tagger: (any ItemTagger)? = nil, queue: TaggingQueue? = nil,
         scan: @escaping @Sendable (CGImage) async throws -> (text: String, barcode: String?) = LabelScanner.scan,
         isBlurry: @escaping @Sendable (CGImage, CGRect?) -> Bool = { QualityCheck.isBlurry($0, region: $1) }) {
        self.processor = processor; self.store = store; self.tagger = tagger; self.queue = queue; self.pipeline = LabelPipeline(scan: scan, isBlurry: isBlurry)
    }

    static func live() -> ReviewModel {
        let store = ImageStore.standard
        return ReviewModel(processor: ItemImageProcessor(cutout: VisionCutoutService(), store: store), store: store,
                           tagger: FoundationModelsTagger(), queue: AppServices.tagging)
    }

    // MARK: derived
    var unresolved: [Photo] { photos.filter { $0.status != .saved && $0.status != .discarded } }
    var isFinished: Bool { !photos.isEmpty && unresolved.isEmpty }
    func photo(_ id: UUID) -> Photo? { photos.first { $0.id == id } }
    /// 1-based position in the batch, for "3 of 5".
    func position(_ id: UUID) -> Int { (photos.firstIndex { $0.id == id } ?? 0) + 1 }

    func askColor(_ p: Photo) -> Bool { p.processed?.colorAmbiguous.first == true && !p.colorDone }
    /// Ask whenever neither the AI nor the user has given a category.
    func askCategory(_ p: Photo) -> Bool { p.processed != nil && effectiveCategory(p) == nil }
    func effectiveCategory(_ p: Photo) -> Category? { p.overrides.category ?? p.ai?.category }
    func effectiveSubcategory(_ p: Photo) -> Subcategory? { p.overrides.subcategory ?? p.ai?.subcategory }
    /// The AI's answer as one chip plus up to two alternatives from its category; nil when there is none or the user chose "Something else".
    func suggestion(_ p: Photo) -> (title: String, alternatives: [Subcategory])? {
        guard let ai = p.ai, !p.showAllChoices else { return nil }
        return (ai.title, identityAlternatives(for: ai.subcategory, in: ai.category))
    }
    func askFit(_ p: Photo) -> Bool { p.processed != nil && !p.fitDone }
    /// Busy background, cut off, box hint, or a failed cut-out: shown as a note with Retake.
    func note(_ p: Photo) -> String? {
        guard let pr = p.processed else { return nil }
        return p.error ?? pr.message ?? (pr.cutoutFailed ? "Cut-out failed, the original is shown." : nil)
    }

    // MARK: processing
    /// Photos are loaded and processed one at a time. `box` is the camera guide for that shot (nil for library picks).
    func begin(count: Int, box: @escaping (Int) -> CGRect? = { _ in nil }, load: @escaping @MainActor (Int) async -> Data?) {
        let start = photos.count
        photos += (0..<count).map { _ in Photo() }
        let ids = photos[start...].map(\.id)
        tasks.append(Task {
            for i in 0..<count { await run(ids[i], data: await load(i), box: box(i)) }
        })
    }

    // MARK: existing items (Review again / Sort these)
    /// One page per saved item, loaded from its stored files, tags and label. Nothing is processed again except the AI
    /// identity call for items that have no aiRaw. Save updates the item in place.
    func beginExisting(_ items: [Item]) {
        for item in items {
            var p = Photo()
            p.existingID = item.id
            let names = item.colorNames.compactMap(ColorName.init(rawValue:))
            // Ask about the colour only while it still shows the extracted name (a differing name was a user answer).
            let ambiguous = names.indices.map { i in
                item.hexColors.indices.contains(i) && ColorExtractor.classify(hex: item.hexColors[i]).name == names[i] && ColorExtractor.classify(hex: item.hexColors[i]).ambiguous
            }
            p.processed = ProcessedImages(itemID: item.id, originalFile: item.originalFile, cutoutFile: item.cutoutFile, displayFile: item.displayFile,
                                          hexColors: item.hexColors, colorNames: names, cutoutFailed: item.cutoutFailed, lastError: item.lastError,
                                          colorAmbiguous: ambiguous)
            p.overrides = item.userOverridesData.flatMap { try? JSONDecoder().decode(ItemTags.self, from: $0) } ?? ItemTags()
            p.label = item.label
            p.labelScan = item.labelScan
            p.fitDone = item.tags.fit != nil
            p.colorDone = ambiguous.first != true
            if let raw = item.aiRawData.flatMap({ try? JSONDecoder().decode(ItemTags.self, from: $0) }),
               let c = raw.category, let s = raw.subcategory, let o = raw.styleOrigin {
                p.ai = IdentityTags(category: c, subcategory: s, styleOrigin: o); p.aiVersion = item.taggerVersion
                p.aiMore = raw; p.aiMore.category = nil; p.aiMore.subcategory = nil; p.aiMore.styleOrigin = nil
                p.tagState = .done
            }
            p.status = .ready
            photos.append(p)
            if p.ai == nil, let tagger { startTagging(p.id, itemID: item.id, tagger: tagger) }
        }
    }

    /// Adjust on a saved item: the candidates were not kept, so run the cut-out again on the stored original.
    func prepareAdjust(_ id: UUID) async {
        guard let p = photo(id)?.processed, p.cutoutResult == nil, photo(id)?.existingID != nil else { return }
        let (processor, url) = (processor, store.url(for: p.originalFile, id: p.itemID))
        let result = await Task.detached { () -> CutoutResult? in
            guard let data = try? Data(contentsOf: url) else { return nil }
            return try? await processor.cutoutResult(forOriginal: data)
        }.value
        update(id) {
            guard let r = result, let pr = $0.processed else { $0.error = "Couldn't find the item in the original photo."; return }
            $0.processed = pr.with(cutoutResult: r); $0.error = nil
        }
    }

    /// Waits for everything started so far (tests).
    func idle() async { var i = 0; while i < tasks.count { await tasks[i].value; i += 1 } }

    private func run(_ id: UUID, data: Data?, box: CGRect?) async {
        var out: ProcessedImages?, failure: String?
        if let data {
            do { out = try await processor.process(data, box: box) } catch { failure = String(describing: error) }
        } else { failure = "unreadable" }
        guard let i = photos.firstIndex(where: { $0.id == id }) else { out.map { store.deleteItem($0.itemID) }; return }
        if photos[i].status == .discarded { out.map { store.deleteItem($0.itemID) }; return }   // discarded while processing
        photos[i].processed = out
        photos[i].error = failure
        photos[i].status = out == nil ? .failed : .ready
        photos[i].ai = nil; photos[i].aiMore = ItemTags(); photos[i].aiVersion = nil; photos[i].tagState = .idle
        if let tagger, let out { startTagging(id, itemID: out.itemID, tagger: tagger) }
    }

    private func startTagging(_ id: UUID, itemID: UUID, tagger: any ItemTagger) {
        let t = Task { await identify(id, itemID: itemID, tagger: tagger) }
        tasks.append(t); liveTagging[id] = t
    }

    /// Calls A, B, C while the user reviews. A shows as soon as it answers. Any failure leaves what was answered so far
    /// (the full lists are shown when A failed); every call is logged. The photo may be discarded or retaken meanwhile.
    private func identify(_ id: UUID, itemID: UUID, tagger: any ItemTagger) async {
        guard let p = photo(id)?.processed, p.itemID == itemID else { return }
        update(id) { $0.tagState = .running }
        let cutout = store.url(for: p.cutoutFile ?? p.originalFile, id: itemID)
        let version = tagger.version
        guard let img = await Task.detached(operation: { ImageCodec.thumbnail(at: cutout, maxPixel: 1024) }).value else {
            update(id) { $0.tagState = .failed("The image could not be read.") }; return
        }
        do {
            let raw = try await TaggingRun.run(tagger: tagger, cutout: img, sink: { [weak self] rec in await self?.log(rec) },
                                               onIdentity: { [weak self] a in await self?.gotIdentity(id, itemID, a, version) })
            guard let i = index(id, itemID) else { return }
            var more = raw; more.category = nil; more.subcategory = nil; more.styleOrigin = nil
            photos[i].aiMore = more; photos[i].tagState = .done
        } catch {
            guard let i = index(id, itemID) else { return }
            photos[i].tagState = .failed(describe(error))
        }
    }
    private func index(_ id: UUID, _ itemID: UUID) -> Int? { photos.firstIndex { $0.id == id && $0.processed?.itemID == itemID && $0.status != .discarded } }
    private func gotIdentity(_ id: UUID, _ itemID: UUID, _ a: IdentityTags, _ version: String) {
        guard let i = index(id, itemID) else { return }
        photos[i].ai = a; photos[i].aiVersion = version
    }

    /// Re-tag: the AI answers again; the user's corrections stay.
    func retag(_ id: UUID) {
        guard let tagger, let p = photo(id)?.processed else { return }
        liveTagging[id]?.cancel()
        update(id) { $0.ai = nil; $0.aiMore = ItemTags(); $0.tagState = .idle; $0.showAllChoices = false }
        startTagging(id, itemID: p.itemID, tagger: tagger)
    }

    private func log(_ rec: AICallRecord) { pendingLogs.append(AIRequestLog(rec)); flushLogs() }
    private func flushLogs() {
        guard let c = logContext, !pendingLogs.isEmpty else { return }
        pendingLogs.forEach(c.insert); pendingLogs = []
        try? c.save()
    }

    // MARK: every tag as chips
    /// The AI's whole answer for a page (calls A, B and C).
    func rawTags(_ p: Photo) -> ItemTags {
        var t = p.aiMore
        if let a = p.ai { t.category = a.category; t.subcategory = a.subcategory; t.styleOrigin = a.styleOrigin }
        return t
    }
    /// aiRaw < label < the user's corrections, as the item will read after Save.
    func effectiveTags(_ p: Photo) -> ItemTags { ItemTags.effective(aiRaw: rawTags(p), label: p.label, userOverrides: p.overrides) }
    func chipGroups(_ p: Photo) -> [TagChipGroup] { effectiveCategory(p).map(TagChipGroup.groups(for:)) ?? [] }
    func chipFields(_ p: Photo) -> Set<TagField> { Set(chipGroups(p).flatMap(\.fields)) }
    /// A dot on the chip: the field is empty, or fabric is `unknown`. Not while the AI is still answering.
    func needsCheck(_ p: Photo, _ f: TagField) -> Bool {
        if p.tagState == .running || (p.tagState == .idle && tagger != nil) { return false }
        let t = effectiveTags(p)
        switch f {
        case .fabric: return t.fabric == nil || t.fabric == .unknown
        case .subcategory: return t.subcategory == nil
        case .styleOrigin: return t.styleOrigin == nil
        case .pattern: return t.pattern == nil
        case .fit: return t.fit == nil
        case .length: return t.length == nil
        case .collar: return t.collar == nil
        case .sleeve: return t.sleeve == nil
        case .dressCodes: return t.dressCodes?.isEmpty ?? true
        case .formality: return t.formality == nil
        case .seasons: return t.seasons == nil
        case .warmth: return t.warmth == nil
        case .statement: return t.statement == nil
        case .closedToe: return t.closedToe == nil
        case .setRole: return false
        }
    }
    /// A chip edit: a user correction only (aiRaw is never touched). The AI's own value, or nil, removes the correction.
    func setField<V: Equatable>(_ id: UUID, _ field: WritableKeyPath<ItemTags, V?>, to value: V?) {
        update(id) {
            $0.overrides = $0.overrides.settingOverride(field, to: value, raw: rawTags($0))
            if (field as AnyKeyPath) == (\ItemTags.fit as AnyKeyPath) { $0.fitDone = true }
        }
    }

    // MARK: actions
    func discard(_ id: UUID) {
        guard let i = photos.firstIndex(where: { $0.id == id }) else { return }
        if photos[i].existingID == nil { photos[i].processed.map { store.deleteItem($0.itemID) } }   // a saved item keeps its files
        photos[i].status = .discarded
        liveTagging[id]?.cancel()
        if retakeID == id { retakeID = nil }
    }

    /// Deletes the photo's files and resets the slot; the view reopens the camera.
    func retake(_ id: UUID) {
        guard let i = photos.firstIndex(where: { $0.id == id }) else { return }
        if photos[i].existingID != nil { retakeID = id; return }   // saved item: keep everything until the new photo arrives
        photos[i].processed.map { store.deleteItem($0.itemID) }
        photos[i] = Photo(); photos[i].id = id
        retakeID = id
    }
    func cancelRetake() { retakeID = nil }   // camera dismissed without a shot: slot is empty, user can retake again or discard

    func replace(_ id: UUID, data: Data, box: CGRect?) async {
        retakeID = nil
        guard let i = photos.firstIndex(where: { $0.id == id }) else { return }
        photos[i].status = .processing
        if let eid = photos[i].existingID { await replaceExisting(id, eid, data: data, box: box) } else { await run(id, data: data, box: box) }
    }

    /// Retake on a saved item: process the new photo as a temporary item, move its files into the saved item's folder,
    /// keep the label, overrides and AI answer.
    private func replaceExisting(_ id: UUID, _ eid: UUID, data: Data, box: CGRect?) async {
        let out = try? await processor.process(data, box: box)
        guard let i = photos.firstIndex(where: { $0.id == id }) else { out.map { store.deleteItem($0.itemID) }; return }
        guard let out, (try? moveFiles(from: out, to: eid)) != nil else {
            out.map { store.deleteItem($0.itemID) }
            photos[i].status = .ready; photos[i].error = "Couldn't use that photo, the old one is kept."
            return
        }
        photos[i].processed = out.moved(to: eid)
        photos[i].error = nil; photos[i].status = .ready
        photos[i].colorDone = false; photos[i].colorAnswer = nil
        NotificationCenter.default.post(name: .itemImagesChanged, object: eid)
    }

    private func moveFiles(from p: ProcessedImages, to eid: UUID) throws {
        for name in [ImageStore.originalName, ImageStore.displayName] { try store.save(try store.load(name, for: p.itemID), named: name, for: eid) }
        if p.cutoutFile != nil { try store.save(try store.load(ImageStore.cutoutName, for: p.itemID), named: ImageStore.cutoutName, for: eid) }
        else { try? FileManager.default.removeItem(at: store.url(for: ImageStore.cutoutName, id: eid)) }
        store.deleteItem(p.itemID)
    }

    func discardAll() { photos.forEach { discard($0.id) } }

    func answerColor(_ id: UUID, _ name: ColorName) { update(id) { $0.colorAnswer = name; $0.colorDone = true } }
    func skipColor(_ id: UUID) { update(id) { $0.colorDone = true } }
    func answerFit(_ id: UUID, _ fit: Fit) { update(id) { $0.overrides.fit = fit; $0.fitDone = true } }
    func answerCategory(_ id: UUID, _ c: Category) {
        update(id) {
            $0.overrides.category = c == $0.ai?.category ? nil : c   // choosing the AI's own answer is not a correction
            if let s = $0.overrides.subcategory, !subcategories(for: c).contains(s) { $0.overrides.subcategory = nil }
        }
    }
    func answerSubcategory(_ id: UUID, _ s: Subcategory) {
        update(id) { $0.overrides.subcategory = s == $0.ai?.subcategory && $0.overrides.category == nil ? nil : s }
    }
    /// Back to the AI's answer: drops both corrections.
    func acceptSuggestion(_ id: UUID) { update(id) { $0.overrides.category = nil; $0.overrides.subcategory = nil } }
    func showAllChoices(_ id: UUID) { update(id) { $0.showAllChoices = true } }
    func skipFit(_ id: UUID) { update(id) { $0.fitDone = true } }
    private func update(_ id: UUID, _ f: (inout Photo) -> Void) { if let i = photos.firstIndex(where: { $0.id == id }) { f(&photos[i]) } }

    /// The question's options: the current name, then the two nearest other named colours.
    func colorChoices(_ p: Photo) -> [ColorName] {
        guard let pr = p.processed, let first = pr.colorNames.first, let hex = pr.hexColors.first else { return [] }
        // ponytail: plain RGB distance, not Lab; only orders the two suggestions, "Other" lists everything.
        func rgb(_ h: String) -> [Double] { let v = UInt32(h, radix: 16) ?? 0; return [Double((v >> 16) & 255), Double((v >> 8) & 255), Double(v & 255)] }
        let me = rgb(hex)
        let near = ColorName.allCases.filter { $0 != first && $0 != .multicolor && $0.referenceHex != nil }
            .sorted { dist(rgb($0.referenceHex!), me) < dist(rgb($1.referenceHex!), me) }
        return [first] + near.prefix(2)
    }
    private func dist(_ a: [Double], _ b: [Double]) -> Double { zip(a, b).reduce(0) { $0 + ($1.0 - $1.1) * ($1.0 - $1.1) } }

    // MARK: cut-out edits (no Vision: the result carries the instance masks)
    enum Recut: Sendable { case tap(CGPoint), chosen([Int]), box(CGRect, chosen: [Int]?) }
    /// Returns true when the new cut-out was written. On failure it sets the photo's `error` (never silent) and writes nothing.
    @discardableResult
    func recut(_ id: UUID, _ how: Recut) async -> Bool {
        guard let p = photo(id)?.processed else { return false }
        guard let r = p.cutoutResult else {
            update(id) { $0.error = "The item couldn't be found in the original photo, so it can't be adjusted. Retake it." }
            return false
        }
        let processor = processor
        let outcome: Result<ProcessedImages, Error> = await Task.detached {
            Result {
                let next: CutoutResult
                switch how {
                case .tap(let pt): next = try r.recut(tap: pt)
                case .chosen(let c): next = try r.recut(chosen: c)
                case .box(let b, let c): next = try r.recut(box: b, chosen: c)
                }
                return try processor.apply(next, to: p)
            }
        }.value
        update(id) {
            switch outcome {
            case .success(let np): $0.processed = np; $0.error = nil; $0.colorDone = false; $0.colorAnswer = nil
            case .failure(let e):
                $0.error = (e as? CutoutError) == .noItemInBox ? "No item inside the box. Move or resize it." : "Couldn't re-cut that choice."
            }
        }
        if case .success = outcome { NotificationCenter.default.post(name: .itemImagesChanged, object: p.itemID) }
        if case .success = outcome { return true } else { return false }
    }

    // MARK: label
    /// Returns a message when the still is rejected (blurry, unreadable); the scanner stays open. nil = draft ready.
    @discardableResult
    func scanLabel(_ id: UUID, photo data: Data, box: CGRect? = nil, liveLines: [String] = [], liveBarcode: String? = nil,
                   pastBrands: [String] = []) async -> String? {
        switch await pipeline.run(photo: data, box: box, liveLines: liveLines, liveBarcode: liveBarcode, pastBrands: pastBrands) {
        case .read(let d, let jpeg): labelDraft = LabelDraft(id: id, data: d, jpeg: jpeg); return nil
        case .blurry: return LabelPipeline.blurryMessage
        case .unreadable: return "Couldn't read that photo, try again"
        }
    }

    /// Stores label.jpg in the item's folder and keeps the (edited) values for Save.
    func confirmLabel(_ data: LabelData) {
        guard let d = labelDraft, let pid = photo(d.id)?.processed?.itemID else { labelDraft = nil; return }
        try? store.save(d.jpeg, named: ImageStore.labelName, for: pid)
        update(d.id) { $0.label = data; $0.labelScan = d.data }
        labelDraft = nil
    }

    // MARK: save
    /// The only place an item reaches the wardrobe. Status: `ready` when tagging is done, off or not wanted; `failed` when
    /// it failed; `tagging` when the AI is still answering and the queue takes over (the live run is dropped).
    @discardableResult func save(_ id: UUID, context: ModelContext) -> Item? {
        guard let i = photos.firstIndex(where: { $0.id == id }), let p = photos[i].processed else { return nil }
        let existing = photos[i].existingID.flatMap { eid in try? context.fetch(FetchDescriptor<Item>(predicate: #Predicate { $0.id == eid })).first }
        if photos[i].existingID != nil, existing == nil { return nil }
        let item = existing ?? Item(p)
        if existing != nil {   // in place: new files, colours and AI answer; tags and label below
            item.originalFile = p.originalFile; item.cutoutFile = p.cutoutFile; item.displayFile = p.displayFile
            item.hexColors = p.hexColors; item.colorNames = p.colorNames.map(\.rawValue)
            item.cutoutFailed = p.cutoutFailed; item.lastError = p.lastError
        }
        if let c = photos[i].colorAnswer, !item.colorNames.isEmpty { item.colorNames[0] = c.rawValue }
        let unfinished = tagger != nil && (photos[i].tagState == .idle || photos[i].tagState == .running)
        if unfinished, queue != nil { liveTagging[id]?.cancel() }
        if photos[i].ai != nil, let v = photos[i].aiVersion {
            let raw = rawTags(photos[i])
            if existing == nil || item.aiRaw != raw { item.replaceRaw(raw, version: v, context: nil) }
        }
        item.userOverridesData = photos[i].overrides == ItemTags() ? nil : try? JSONEncoder().encode(photos[i].overrides)
        item.labelData = photos[i].label.flatMap { try? JSONEncoder().encode($0) }
        item.labelScanData = photos[i].labelScan.flatMap { try? JSONEncoder().encode($0) } ?? item.labelScanData
        if unfinished, queue != nil { item.status = .tagging }
        else if case .failed(let e) = photos[i].tagState, (tagger as? AvailabilityReporting)?.unavailableReason == nil { item.status = .failed; item.lastError = e }
        else { item.status = .ready }
        if existing == nil { context.insert(item) }
        try? context.save()
        if existing != nil { NotificationCenter.default.post(name: .itemImagesChanged, object: item.id) }
        photos[i].status = .saved
        if item.status == .tagging, let queue { let iid = item.id; Task { await queue.enqueue([iid]) } }
        return item
    }
}

private extension ProcessedImages {
    func with(cutoutResult r: CutoutResult) -> ProcessedImages {
        ProcessedImages(itemID: itemID, originalFile: originalFile, cutoutFile: cutoutFile, displayFile: displayFile, hexColors: hexColors,
                        colorNames: colorNames, cutoutFailed: cutoutFailed, lastError: lastError, verdict: verdict, colorAmbiguous: colorAmbiguous,
                        hint: hint, cutoutResult: r)
    }
    /// The same result under another item id (its files were moved there).
    func moved(to id: UUID) -> ProcessedImages {
        ProcessedImages(itemID: id, originalFile: originalFile, cutoutFile: cutoutFile, displayFile: displayFile, hexColors: hexColors,
                        colorNames: colorNames, cutoutFailed: cutoutFailed, lastError: lastError, verdict: verdict, colorAmbiguous: colorAmbiguous,
                        hint: hint, cutoutResult: cutoutResult)
    }
}
