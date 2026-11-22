import CoreGraphics
import Foundation
import Observation
import StyleEngine
import SwiftData
import WardrobeImaging

/// Holds processed photos while the user reviews them. Nothing touches SwiftData until `save`;
/// `discard` deletes that photo's files. Plain observable so tests drive it with a fake cut-out provider.
/// The façade the review screen uses: the work is in `CaptureProcessor` (cut-out), `TaggingCoordinator` (live AI),
/// `ReviewQuestions` (what to ask) and `ReviewSaver` (persisting).
@MainActor @Observable final class ReviewModel: Identifiable {
    nonisolated var id: ObjectIdentifier { ObjectIdentifier(self) }
    typealias Recut = CaptureRecut
    /// A scanned label waiting for the user to edit and confirm.
    struct LabelDraft: Identifiable { let id: UUID; var data: LabelData; let jpeg: Data }

    private(set) var photos: [Photo] = []
    /// Set by `retake`: the view reopens the camera and calls `replace` for this photo.
    private(set) var retakeID: UUID?
    var labelDraft: LabelDraft?
    /// True from `begin` until every photo is cut out and its tagging has answered, failed or timed out: the review shows one progress screen.
    private(set) var analysing = false
    /// How long one photo may wait for the AI before the review opens with what is there.
    var tagTimeout: Duration {
        get { tagging?.timeout ?? .seconds(30) }
        set { tagging?.timeout = newValue }
    }
    /// Items saved with "Make a product photo after saving"; the screen that presented the review runs them once it is gone.
    func takeProductQueue() -> [UUID] { saver.takeProductQueue() }

    let store: ImageStore
    private let capture: CaptureProcessor
    private let tagging: TaggingCoordinator?   // nil: no tagger, the AI is off for this review
    private let saver: ReviewSaver
    private let pipeline: LabelPipeline
    private let queue: TaggingQueue?
    private let prints: any FeaturePrinting
    private var tasks: [Task<Void, Never>] = []
    /// Where AI call rows are written. Rows made before it is set are kept and written when it arrives.
    var logContext: ModelContext? { didSet { flushLogs() } }
    private var pendingLogs: [AIRequestLog] = []

    init(processor: ItemImageProcessor, store: ImageStore, tagger: (any ItemTagger)? = nil, queue: TaggingQueue? = nil,
         prints: any FeaturePrinting = VisionFeaturePrinting(),
         scan: @escaping @Sendable (CGImage) async throws -> (text: String, barcode: String?) = LabelScanner.scan,
         isBlurry: @escaping @Sendable (CGImage, CGRect?) -> Bool = { QualityCheck.isBlurry($0, region: $1) }) {
        self.store = store; self.queue = queue; self.prints = prints
        capture = CaptureProcessor(processor: processor, store: store)
        tagging = tagger.map(TaggingCoordinator.init(tagger:))
        saver = ReviewSaver(store: store)
        pipeline = LabelPipeline(scan: scan, isBlurry: isBlurry)
    }

    /// The review the app opens: Vision cut-out, the environment's tagger and background queue.
    static func live(_ env: AppEnvironment) -> ReviewModel {
        ReviewModel(processor: ItemImageProcessor(cutout: VisionCutoutService(), store: env.store), store: env.store,
                    tagger: env.provider.makeTagger(), queue: env.tagging)
    }

    // MARK: derived
    var unresolved: [Photo] { photos.filter { $0.status != .saved && $0.status != .discarded } }
    var isFinished: Bool { !photos.isEmpty && unresolved.isEmpty }
    func photo(_ id: UUID) -> Photo? { photos.first { $0.id == id } }
    /// 1-based position in the batch, for "3 of 5".
    func position(_ id: UUID) -> Int { (photos.firstIndex { $0.id == id } ?? 0) + 1 }

    // MARK: questions (see ReviewQuestions)
    func askColor(_ p: Photo) -> Bool { ReviewQuestions.askColor(p) }
    func askCategory(_ p: Photo) -> Bool { ReviewQuestions.askCategory(p) }
    func askFit(_ p: Photo) -> Bool { ReviewQuestions.askFit(p) }
    func effectiveCategory(_ p: Photo) -> Category? { ReviewQuestions.effectiveCategory(p) }
    func effectiveSubcategory(_ p: Photo) -> Subcategory? { ReviewQuestions.effectiveSubcategory(p) }
    func suggestion(_ p: Photo) -> (title: String, alternatives: [Subcategory])? { ReviewQuestions.suggestion(p) }
    func colorNames(_ p: Photo) -> [ColorName] { ReviewQuestions.colorNames(p) }
    func colorChoices(_ p: Photo) -> [ColorName] { ReviewQuestions.colorChoices(p) }
    func needsCheck(_ p: Photo, _ f: TagField) -> Bool { ReviewQuestions.needsCheck(p, f, hasTagger: tagging != nil) }

    /// Per-photo line on the progress screen.
    func stage(_ p: Photo) -> String {
        switch p.status {
        case .processing: return "Cutting out…"
        case .failed: return "Couldn't read this photo"
        default:
            switch p.tagState {
            case .done: return "Done"
            case .failed: return "Done, check the details"
            default: return tagging == nil ? "Done" : "Reading the details…"
            }
        }
    }
    /// Photos finished with cut-out and AI, for the progress bar.
    var settledCount: Int { photos.filter { stage($0).hasPrefix("Done") || $0.status == .failed || $0.status == .discarded }.count }
    /// Busy background, cut off, box hint, or a failed cut-out: shown as a note with Retake.
    func note(_ p: Photo) -> String? {
        guard let pr = p.processed else { return nil }
        return p.error ?? pr.message ?? (pr.cutoutFailed ? "Cut-out failed, the original is shown." : nil)
    }

    // MARK: every tag as chips
    func rawTags(_ p: Photo) -> ItemTags { p.rawTags }
    func effectiveTags(_ p: Photo) -> ItemTags { p.effectiveTags }
    func chipGroups(_ p: Photo) -> [TagChipGroup] { effectiveCategory(p).map(TagChipGroup.groups(for:)) ?? [] }
    func chipFields(_ p: Photo) -> Set<TagField> { Set(chipGroups(p).flatMap(\.fields)) }

    // MARK: processing
    /// Photos are loaded and processed one at a time. `box` is the camera guide for that shot (nil for library picks).
    func begin(count: Int, box: @escaping (Int) -> CGRect? = { _ in nil }, load: @escaping @MainActor (Int) async -> Data?) {
        let start = photos.count
        photos += (0..<count).map { _ in Photo() }
        let ids = photos[start...].map(\.id)
        analysing = true
        tasks.append(Task {
            for i in 0..<count { await run(ids[i], data: await load(i), box: box(i)) }
            for id in ids { await awaitTagging(id) }   // the AI runs while the next photo is cut out; wait for the rest here
            analysing = false
        })
    }

    /// One page per saved item (Review again / Sort these). Nothing is processed again except the AI
    /// identity call for items that have no aiRaw. Save updates the item in place.
    func beginExisting(_ items: [Item]) {
        for item in items {
            let p = Photo(existing: item)
            photos.append(p)
            if p.ai == nil { startTagging(p.id, itemID: item.id) }
        }
    }

    /// Adjust on a saved item: the candidates were not kept, so run the cut-out again on the stored original.
    func prepareAdjust(_ id: UUID) async {
        guard let p = photo(id)?.processed, p.cutoutResult == nil, photo(id)?.existingID != nil else { return }
        let result = await capture.cutoutResult(ofStored: p)
        update(id) {
            guard let r = result, let pr = $0.processed else { $0.error = "Couldn't find the item in the original photo."; return }
            $0.processed = pr.with(cutoutResult: r); $0.error = nil
        }
    }

    /// Waits for everything started so far (tests).
    func idle() async {
        var i = 0; while i < tasks.count { await tasks[i].value; i += 1 }
        await tagging?.idle()
    }

    private func run(_ id: UUID, data: Data?, box: CGRect?) async {
        let (out, failure) = await capture.process(data, box: box)
        guard let i = photos.firstIndex(where: { $0.id == id }) else { capture.discard(out); return }
        if photos[i].status == .discarded { capture.discard(out); return }   // discarded while processing
        photos[i].processed = out
        photos[i].error = failure
        photos[i].status = out == nil ? .failed : .ready
        photos[i].ai = nil; photos[i].aiMore = ItemTags(); photos[i].aiVersion = nil; photos[i].tagState = .idle
        if let out {
            startTagging(id, itemID: out.itemID)
            await computePrint(id, out)
        }
    }

    // MARK: duplicate check
    /// The cut-out's feature print (off the main thread), then the check against what is already in the wardrobe.
    private func computePrint(_ id: UUID, _ out: ProcessedImages) async {
        let (url, prints) = (store.url(for: out.displayFile, id: out.itemID), prints)
        let data = await Task.detached { ImageCodec.thumbnail(at: url, maxPixel: 512).flatMap { prints.compute(from: $0) } }.value
        update(id) { $0.featurePrint = data }
        refreshDuplicate(id)
    }

    /// Sets or clears the offer. Runs when the print arrives and again when the AI names the subcategory (only like is compared with like).
    private func refreshDuplicate(_ id: UUID) {
        guard let p = photo(id), p.existingID == nil, !p.duplicateDismissed, let print = p.featurePrint, let c = logContext else { return }
        let items = (try? c.fetch(FetchDescriptor<Item>())) ?? []
        let byId = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let match = DuplicateCheck.match(subcategory: effectiveSubcategory(p),
                                         among: items.map { DuplicateCandidate(id: $0.id, subcategory: $0.tags.subcategory) },
                                         distance: { [prints] in byId[$0]?.featurePrintData.flatMap { prints.distance(print, $0) } })
        update(id) { $0.duplicate = match.flatMap { m in byId[m.id].map { DuplicateOffer(itemID: $0.id, name: $0.name, distance: m.distance) } } }
    }

    /// "Different": keep both; the question is not asked again for this photo.
    func keepBoth(_ id: UUID) { update(id) { $0.duplicate = nil; $0.duplicateDismissed = true } }
    /// "Same": the new photo is thrown away (files deleted); the existing item stays as it is.
    func discardAsDuplicate(_ id: UUID) { discard(id) }

    // MARK: live tagging
    /// Waits for a photo's tagging, at most `tagTimeout`; on timeout it is cancelled and the photo shows as failed (manual questions stay).
    private func awaitTagging(_ id: UUID) async {
        await tagging?.wait(for: id) { [self] in
            update(id) { if $0.tagState == .running || $0.tagState == .idle { $0.tagState = .failed("The AI took too long.") } }
        }
    }

    private func startTagging(_ id: UUID, itemID: UUID) {
        tagging?.start(id) { [self] in await identify(id, itemID: itemID) }
    }

    /// Calls A, B, C while the user reviews. A shows as soon as it answers. Any failure leaves what was answered so far
    /// (the full lists are shown when A failed); every call is logged. The photo may be discarded or retaken meanwhile.
    private func identify(_ id: UUID, itemID: UUID) async {
        guard let tagging, let p = photo(id)?.processed, p.itemID == itemID else { return }
        update(id) { $0.tagState = .running }
        let version = tagging.tagger.version
        guard let img = await tagging.cutoutImage(at: store.url(for: p.cutoutFile ?? p.originalFile, id: itemID)) else {
            update(id) { $0.tagState = .failed("The image could not be read.") }; return
        }
        do {
            let raw = try await tagging.run(img, sink: { [weak self] rec in await self?.log(rec) },
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
        refreshDuplicate(id)
    }

    /// Re-tag: the AI answers again; the user's corrections stay.
    func retag(_ id: UUID) {
        guard tagging != nil, let p = photo(id)?.processed else { return }
        tagging?.cancel(id)
        update(id) { $0.ai = nil; $0.aiMore = ItemTags(); $0.tagState = .idle; $0.showAllChoices = false }
        startTagging(id, itemID: p.itemID)
    }

    private func log(_ rec: AICallRecord) { pendingLogs.append(AIRequestLog(rec)); flushLogs() }
    private func flushLogs() {
        guard let c = logContext, !pendingLogs.isEmpty else { return }
        pendingLogs.forEach(c.insert); pendingLogs = []
        try? c.save()
    }

    // MARK: actions
    /// A chip edit: a user correction only (aiRaw is never touched). The AI's own value, or nil, removes the correction.
    func setField<V: Equatable>(_ id: UUID, _ field: WritableKeyPath<ItemTags, V?>, to value: V?) {
        update(id) {
            $0.overrides = $0.overrides.settingOverride(field, to: value, raw: $0.rawTags)
            if (field as AnyKeyPath) == (\ItemTags.fit as AnyKeyPath) { $0.fitDone = true }
        }
    }

    func discard(_ id: UUID) {
        guard let i = photos.firstIndex(where: { $0.id == id }) else { return }
        if photos[i].existingID == nil { capture.discard(photos[i].processed) }   // a saved item keeps its files
        photos[i].status = .discarded
        tagging?.cancel(id)
        if retakeID == id { retakeID = nil }
    }

    /// Deletes the photo's files and resets the slot; the view reopens the camera.
    func retake(_ id: UUID) {
        guard let i = photos.firstIndex(where: { $0.id == id }) else { return }
        if photos[i].existingID != nil { retakeID = id; return }   // saved item: keep everything until the new photo arrives
        capture.discard(photos[i].processed)
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
        let out = await capture.process(data, box: box).out
        guard let i = photos.firstIndex(where: { $0.id == id }) else { capture.discard(out); return }
        guard let out, let moved = capture.adopt(out, as: eid) else {
            photos[i].status = .ready; photos[i].error = "Couldn't use that photo, the old one is kept."
            return
        }
        photos[i].processed = moved
        photos[i].error = nil; photos[i].status = .ready
        photos[i].colorDone = false; photos[i].colorAnswer = nil
        NotificationCenter.default.post(name: .itemImagesChanged, object: eid)
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

    // MARK: cut-out edits (no Vision: the result carries the instance masks)
    /// Returns true when the new cut-out was written. On failure it sets the photo's `error` (never silent) and writes nothing.
    @discardableResult
    func recut(_ id: UUID, _ how: Recut) async -> Bool {
        guard let p = photo(id)?.processed else { return false }
        guard let r = p.cutoutResult else {
            update(id) { $0.error = "The item couldn't be found in the original photo, so it can't be adjusted. Retake it." }
            return false
        }
        let outcome = await capture.recut(how, of: r, applyingTo: p)
        update(id) {
            switch outcome {
            case .success(let np): $0.processed = np; $0.error = nil; $0.colorDone = false; $0.colorAnswer = nil
            case .failure(let e):
                $0.error = (e as? CutoutError) == .noItemInBox ? "No item inside the box. Move or resize it." : "Couldn't re-cut that choice."
            }
        }
        if case .success = outcome { NotificationCenter.default.post(name: .itemImagesChanged, object: p.itemID); return true }
        return false
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
    /// The only place an item reaches the wardrobe (see `ReviewSaver`). When the AI is still answering and a queue exists,
    /// the queue takes over and the live run is dropped.
    @discardableResult func save(_ id: UUID, context: ModelContext, makeProduct: Bool = false) -> Item? {
        guard let i = photos.firstIndex(where: { $0.id == id }) else { return nil }
        let unfinished = tagging != nil && (photos[i].tagState == .idle || photos[i].tagState == .running)
        let handOff = unfinished && queue != nil
        guard let item = saver.save(photos[i], in: context, handOffToQueue: handOff, modelOff: tagging?.unavailableReason != nil) else { return nil }
        if handOff { tagging?.cancel(id) }
        photos[i].status = .saved
        if makeProduct { saver.queueProduct(item.id) }
        if item.status == .tagging, let queue { let iid = item.id; Task { await queue.enqueue([iid]) } }
        return item
    }
}
