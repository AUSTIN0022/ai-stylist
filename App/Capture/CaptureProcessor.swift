import CoreGraphics
import Foundation
import WardrobeImaging

/// A cut-out edit asked for on the review page.
enum CaptureRecut: Sendable { case tap(CGPoint), chosen([Int]), box(CGRect, chosen: [Int]?) }

/// Photo bytes -> stored images: cut-out, re-cut, and moving a retaken photo into a saved item's folder. No review state in here.
struct CaptureProcessor: Sendable {
    let processor: ItemImageProcessor
    let store: ImageStore

    /// `data` nil means the photo could not be loaded.
    func process(_ data: Data?, box: CGRect?) async -> (out: ProcessedImages?, failure: String?) {
        guard let data else { return (nil, "unreadable") }
        do { return (try await processor.process(data, box: box), nil) } catch { return (nil, String(describing: error)) }
    }

    /// Deletes a processed photo's files (an unsaved photo that is discarded, replaced or lost).
    func discard(_ out: ProcessedImages?) { out.map { store.deleteItem($0.itemID) } }

    /// Adjust on a saved item: the candidates were not kept, so run the cut-out again on the stored original.
    func cutoutResult(ofStored p: ProcessedImages) async -> CutoutResult? {
        let (processor, url) = (processor, store.url(for: p.originalFile, id: p.itemID))
        return await Task.detached { () -> CutoutResult? in
            guard let data = try? Data(contentsOf: url) else { return nil }
            return try? await processor.cutoutResult(forOriginal: data)
        }.value
    }

    /// Re-cuts from the instance masks the result carries (no Vision) and writes the new files.
    func recut(_ how: CaptureRecut, of r: CutoutResult, applyingTo p: ProcessedImages) async -> Result<ProcessedImages, Error> {
        let processor = processor
        return await Task.detached {
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
    }

    /// Retake on a saved item: moves the temporary item's files into the saved item's folder. nil (and `out` deleted) on failure.
    func adopt(_ out: ProcessedImages, as eid: UUID) -> ProcessedImages? {
        guard (try? moveFiles(from: out, to: eid)) != nil else { store.deleteItem(out.itemID); return nil }
        return out.moved(to: eid)
    }

    private func moveFiles(from p: ProcessedImages, to eid: UUID) throws {
        for name in [ImageStore.originalName, ImageStore.displayName] { try store.save(try store.load(name, for: p.itemID), named: name, for: eid) }
        if p.cutoutFile != nil { try store.save(try store.load(ImageStore.cutoutName, for: p.itemID), named: ImageStore.cutoutName, for: eid) }
        else { try? FileManager.default.removeItem(at: store.url(for: ImageStore.cutoutName, id: eid)) }
        store.deleteItem(p.itemID)
    }
}

extension ProcessedImages {
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
