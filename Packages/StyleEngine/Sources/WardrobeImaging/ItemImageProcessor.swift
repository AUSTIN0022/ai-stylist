import CoreGraphics
import Foundation
import StyleEngine

public struct ProcessedImages: Sendable {
    public let itemID: UUID
    public let originalFile: String
    public let cutoutFile: String?        // nil when the cut-out failed
    public let displayFile: String
    public let hexColors: [String]
    public let colorNames: [ColorName]
    public let cutoutFailed: Bool
    public let lastError: String?
    public let verdict: QualityVerdict
    /// One flag per colour name: ask the user about these.
    public let colorAmbiguous: [Bool]
    /// Set when the camera box held no item ("Put the item inside the box").
    public let hint: String?
    /// Candidates and instance masks, so the review can re-cut without Vision. Nil when the cut-out failed.
    public let cutoutResult: CutoutResult?

    public init(itemID: UUID, originalFile: String, cutoutFile: String?, displayFile: String, hexColors: [String], colorNames: [ColorName],
                cutoutFailed: Bool, lastError: String? = nil, verdict: QualityVerdict = .ok, colorAmbiguous: [Bool], hint: String? = nil,
                cutoutResult: CutoutResult? = nil) {
        self.itemID = itemID; self.originalFile = originalFile; self.cutoutFile = cutoutFile; self.displayFile = displayFile
        self.hexColors = hexColors; self.colorNames = colorNames; self.cutoutFailed = cutoutFailed; self.lastError = lastError
        self.verdict = verdict; self.colorAmbiguous = colorAmbiguous; self.hint = hint; self.cutoutResult = cutoutResult
    }
    /// What to show the user: the box hint, else the verdict text.
    public var message: String? { hint ?? verdict.message }
}

public enum ProcessingError: Error { case unreadableImage }

/// Photo bytes -> files on disk + colours + quality verdict. One photo at a time. No database here.
public struct ItemImageProcessor: Sendable {
    public static let workSide = 2048, displaySide = 1024
    let cutout: any CutoutProviding
    let store: ImageStore

    public init(cutout: any CutoutProviding, store: ImageStore) { self.cutout = cutout; self.store = store }

    /// `box`: the camera guide in photo coordinates (normalised, top-left origin); nil for library photos.
    public func process(_ data: Data, box: CGRect? = nil) async throws -> ProcessedImages {
        guard let full = ImageCodec.decode(data), let originalJPEG = ImageCodec.jpegData(full, quality: 0.92) else {
            throw ProcessingError.unreadableImage
        }
        let work = Compositor.downscaled(full, maxSide: Self.workSide)
        var result: CutoutResult?, failure: String?, hint: String?
        do { result = try await cutout.cutout(from: work, box: box) } catch {
            failure = String(describing: error)
            if case CutoutError.noItemInBox = error { hint = SubjectSelector.boxHint }
        }

        // Flagged photos are not blocked: the verdict travels with the item and the user decides.
        let verdict = hint != nil ? .noClearItem : QualityCheck.check(image: work, mask: result?.mask)

        let display = result.map { Catalogue.render(cutout: $0.cutout, original: work, mask: $0.mask, category: nil) }
            ?? Compositor.centerCropSquare(work, side: Self.displaySide)
        let colors = result.map { ColorExtractor.extract(from: $0.cutout) }
        let id = UUID()
        do {
            try store.save(originalJPEG, named: ImageStore.originalName, for: id)
            if let r = result, let png = ImageCodec.pngData(r.cutout) { try store.save(png, named: ImageStore.cutoutName, for: id) }
            guard let displayJPEG = ImageCodec.jpegData(display, quality: 0.9) else { throw ProcessingError.unreadableImage }
            try store.save(displayJPEG, named: ImageStore.displayName, for: id)
        } catch { store.deleteItem(id); throw error }

        return ProcessedImages(itemID: id, originalFile: ImageStore.originalName,
                               cutoutFile: result == nil ? nil : ImageStore.cutoutName, displayFile: ImageStore.displayName,
                               hexColors: colors?.hexes ?? [], colorNames: colors?.names ?? [],
                               cutoutFailed: result == nil, lastError: failure, verdict: verdict,
                               colorAmbiguous: colors?.ambiguous ?? [], hint: hint, cutoutResult: result)
    }

    /// Runs the cut-out on a stored original (Review again: the candidates were not kept). Writes nothing.
    public func cutoutResult(forOriginal data: Data, box: CGRect? = nil) async throws -> CutoutResult {
        guard let full = ImageCodec.decode(data) else { throw ProcessingError.unreadableImage }
        return try await cutout.cutout(from: Compositor.downscaled(full, maxSide: Self.workSide), box: box)
    }

    /// Writes a re-cut (from `CutoutResult.recut`) over the item's cutout.png and display.jpg and redoes colours and verdict.
    public func apply(_ result: CutoutResult, to p: ProcessedImages) throws -> ProcessedImages {
        guard let png = ImageCodec.pngData(result.cutout),
              let displayJPEG = ImageCodec.jpegData(Catalogue.render(cutout: result.cutout, original: result.session?.image, mask: result.mask, category: nil), quality: 0.9)
        else { throw ProcessingError.unreadableImage }
        try store.save(png, named: ImageStore.cutoutName, for: p.itemID)
        try store.save(displayJPEG, named: ImageStore.displayName, for: p.itemID)
        let colors = ColorExtractor.extract(from: result.cutout)
        let verdict = result.session.map { QualityCheck.check(image: $0.image, mask: result.mask) } ?? p.verdict
        return ProcessedImages(itemID: p.itemID, originalFile: p.originalFile, cutoutFile: ImageStore.cutoutName, displayFile: ImageStore.displayName,
                               hexColors: colors.hexes, colorNames: colors.names, cutoutFailed: false, lastError: nil, verdict: verdict,
                               colorAmbiguous: colors.ambiguous, hint: nil, cutoutResult: result)
    }

    /// Rebuilds display.jpg from the stored cut-out (and original, for white balance). Leaves cutout.png and original.jpg untouched.
    /// No stored mask: the surround is the original's outer frame. `category` squares the garment up (see `Catalogue`).
    public func refreshDisplay(for id: UUID, category: StyleEngine.Category? = nil) throws {
        guard let cut = ImageCodec.decode(try store.load(ImageStore.cutoutName, for: id)) else { throw ProcessingError.unreadableImage }
        let original = (try? store.load(ImageStore.originalName, for: id)).flatMap { ImageCodec.decode($0, maxPixel: 384) }
        guard let jpeg = ImageCodec.jpegData(Catalogue.render(cutout: cut, original: original, mask: nil, category: category), quality: 0.9)
        else { throw ProcessingError.unreadableImage }
        try store.save(jpeg, named: ImageStore.displayName, for: id)
    }

    /// Image Playground's result (a temporary file) -> product.jpg, 1200x1500 on the catalogue backdrop #F4F4F2. The generated image is
    /// NOT cut out again (the re-cut looked jagged): the injected provider's mask only measures the subject, then `Catalogue.productFrame`
    /// crops 4:5 around it and levels the backdrop. No subject found: centre-crop 4:5. Writes nothing when the file cannot be read.
    public func saveProductPhoto(from url: URL, for id: UUID) async throws {
        guard let img = ImageCodec.decode(try Data(contentsOf: url)) else { throw ProcessingError.unreadableImage }
        let work = Compositor.downscaled(img, maxSide: Self.workSide)
        let framed: CGImage
        if let m = (try? await cutout.cutout(from: work, box: nil))?.mask, let b = m.bounds {
            framed = Catalogue.productFrame(work, subject: CGRect(x: b.minX / Double(m.width), y: b.minY / Double(m.height),
                                                                  width: b.width / Double(m.width), height: b.height / Double(m.height)))
        } else {
            framed = Self.centreCrop4x5(work)
        }
        guard let jpeg = ImageCodec.jpegData(framed, quality: 0.9) else { throw ProcessingError.unreadableImage }
        try store.save(jpeg, named: ImageStore.productName, for: id)
    }

    static func centreCrop4x5(_ image: CGImage) -> CGImage {
        let w = Catalogue.canvasWidth, h = Catalogue.canvasHeight
        let cw = min(Double(image.width), Double(image.height) * 4 / 5), ch = cw * 5 / 4
        let rect = CGRect(x: (Double(image.width) - cw) / 2, y: (Double(image.height) - ch) / 2, width: cw, height: ch).integral
        guard let crop = image.cropping(to: rect),
              let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return image }
        ctx.interpolationQuality = .high
        ctx.draw(crop, in: CGRect(x: 0, y: 0, width: w, height: h))
        return ctx.makeImage() ?? image
    }

    /// Photos are loaded, processed and released one at a time (memory stays flat for 20 photos).
    public func processBatch(count: Int, box: CGRect? = nil, load: @MainActor (Int) async -> Data?,
                             onResult: @MainActor (Int, Result<ProcessedImages, Error>) -> Void) async {
        for i in 0..<count {
            let outcome: Result<ProcessedImages, Error>
            if let data = await load(i) {
                do { outcome = .success(try await process(data, box: box)) } catch { outcome = .failure(error) }
            } else { outcome = .failure(ProcessingError.unreadableImage) }
            await onResult(i, outcome)
        }
    }
}
