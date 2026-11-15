import Foundation
import StyleEngine
import SwiftData
import WardrobeImaging

/// The only place a reviewed photo reaches the wardrobe: writes (or updates in place) the `Item`, and keeps the queue of items
/// saved with "Make a product photo after saving" for the screen that presented the review.
@MainActor final class ReviewSaver {
    private let store: ImageStore
    private var productQueue: [UUID] = []

    init(store: ImageStore) { self.store = store }

    func takeProductQueue() -> [UUID] { defer { productQueue = [] }; return productQueue }
    func queueProduct(_ id: UUID) { productQueue.append(id) }

    /// Status: `ready` when tagging is done, off or not wanted; `failed` when it failed; `tagging` when the AI is still answering
    /// and the queue takes over (`handOffToQueue`). nil when the page has no images or its saved item is gone. `modelOff` = the AI cannot run.
    func save(_ photo: ReviewModel.Photo, in context: ModelContext, handOffToQueue: Bool, modelOff: Bool) -> Item? {
        guard let p = photo.processed else { return nil }
        let existing = photo.existingID.flatMap { eid in try? context.fetch(FetchDescriptor<Item>(predicate: #Predicate { $0.id == eid })).first }
        if photo.existingID != nil, existing == nil { return nil }
        let item = existing ?? Item(p)
        if existing != nil {   // in place: new files, colours and AI answer; tags and label below
            item.originalFile = p.originalFile; item.cutoutFile = p.cutoutFile; item.displayFile = p.displayFile
            item.hexColors = p.hexColors; item.colorNames = p.colorNames.map(\.rawValue)
            item.cutoutFailed = p.cutoutFailed; item.lastError = p.lastError
        }
        if let c = photo.colorAnswer { item.setColour(c, context: nil) }
        if photo.ai != nil, let v = photo.aiVersion {
            let raw = photo.rawTags
            if existing == nil || item.aiRaw != raw { item.replaceRaw(raw, version: v, context: nil) }
        }
        item.userOverridesData = photo.overrides == ItemTags() ? nil : try? JSONEncoder().encode(photo.overrides)
        item.labelData = photo.label.flatMap { try? JSONEncoder().encode($0) }
        item.labelScanData = photo.labelScan.flatMap { try? JSONEncoder().encode($0) } ?? item.labelScanData
        if handOffToQueue { item.status = .tagging }
        else if case .failed(let e) = photo.tagState, !modelOff { item.status = .failed; item.lastError = e }
        else { item.status = .ready }
        if existing == nil { context.insert(item) }
        try? context.save()
        if p.cutoutFile != nil { FabricSwatch.save(for: item.id, store: store) }   // colour and texture reference; nil patch = none
        if existing != nil { NotificationCenter.default.post(name: .itemImagesChanged, object: item.id) }
        return item
    }
}
