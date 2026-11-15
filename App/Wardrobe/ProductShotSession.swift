import CoreGraphics
import Foundation
import Observation
import StyleEngine
import SwiftData
import WardrobeImaging

struct ProductShotCancelled: LocalizedError { var errorDescription: String? { "Cancelled" } }

/// One Image Playground sheet at a time: prompt + swatch in, `product.jpg` out, one AIRequestLog row per sheet.
/// The sheet itself lives in `ProductShotSheet`; it calls `deliver` / `cancel`, and tests call them directly (no real generation).
@MainActor @Observable final class ProductShotSession {
    enum Outcome: Equatable { case saved, cancelled, failed(String) }

    /// What the overlay over the item image shows. `sheet`: Apple's sheet is up (it covers the overlay).
    enum Overlay: Equatable { case idle, preparing, sheet, saving }

    var isPresented = false
    var context: ModelContext?
    private(set) var overlay = Overlay.idle
    private(set) var errorMessage: String?
    private(set) var askingSleeve = false   // the one-tap "Sleeve?" question is up
    private(set) var prompt = ""
    private(set) var shortConcepts: [String] = []   // default style: 2-3 short phrases (long sentences get refused)
    private(set) var title = ""
    private(set) var sentence = ""   // default style: Austin's wording (see ProductShotPrompt.sentence)
    private(set) var sourceImage: CGImage?   // the shape template for this garment, else the cut-out on white
    private(set) var swatch: CGImage?        // fabric patch: colour and texture
    private(set) var isBusy = false
    let store: ImageStore
    let cutout: any CutoutProviding
    let templates: TemplateStore
    @ObservationIgnored private var waiting: CheckedContinuation<URL, Error>?
    @ObservationIgnored private var sleeveAnswer: CheckedContinuation<Sleeve?, Never>?

    init(store: ImageStore = .standard, context: ModelContext? = nil, cutout: any CutoutProviding = VisionCutoutService(),
         templates: TemplateStore = .standard) {
        self.store = store; self.context = context; self.cutout = cutout; self.templates = templates
    }

    /// Builds (or reuses) the item's descriptor, shows the sheet and waits for Use / Cancel. `rebuild` ignores the stored descriptor.
    func make(for item: Item, rebuild: Bool = false) async -> Outcome {
        guard !isBusy else { return .failed("Another product photo is in progress.") }
        isBusy = true; overlay = .preparing; errorMessage = nil
        defer { isBusy = false; overlay = .idle }
        await Task.yield()   // let the dim + sparkle render before the slow part

        if ProductShotPrompt.needsSleeve(item.tags) {   // no sleeve tag: ask, never guess (Image Playground would draw long sleeves)
            guard let sl = await askSleeve() else { return .cancelled }
            item.setOverride(\.sleeve, to: sl, context: context)
        }
        let id = item.id, fabricURL = store.url(for: ImageStore.fabricName, id: id)
        if item.cutoutFile != nil, !FileManager.default.fileExists(atPath: fabricURL.path) { FabricSwatch.save(for: id, store: store) }
        swatch = FileManager.default.fileExists(atPath: fabricURL.path) ? ImageCodec.thumbnail(at: fabricURL, maxPixel: FabricSwatch.side) : nil
        let tags = item.tags
        if case .template(let shape) = ProductTemplate.source(for: tags, available: templates.available),
           let url = templates.url(for: shape), let t = ImageCodec.thumbnail(at: url, maxPixel: 1024) {
            sourceImage = t
        } else {
            guard let cut = ImageCodec.thumbnail(at: store.url(for: item.cutoutFile ?? item.originalFile, id: id), maxPixel: 1024) else {
                return fail("The image could not be read.")
            }
            sourceImage = Self.onWhite(cut)
        }

        let swatchFile = swatch == nil ? nil : ImageStore.fabricName
        let colourNames = item.colorNames.compactMap(ColorName.init(rawValue:))
        var d = item.productDescriptor
        if rebuild || d == nil || d?.swatchFile != swatchFile {
            d = ProductDescriptor(prompt: ProductShotPrompt.make(for: tags, colours: colourNames, hexes: item.hexColors, label: item.label, swatch: swatch != nil),
                                  swatchFile: swatchFile, hexes: Array(item.hexColors.prefix(1)))
        }
        let desc = d!
        prompt = desc.prompt
        shortConcepts = ProductShotPrompt.shortConcepts(for: tags, colours: colourNames)
        title = item.name
        sentence = ProductShotPrompt.sentence(for: tags, colours: colourNames, hexes: item.hexColors)
        let processor = ItemImageProcessor(cutout: cutout, store: store)
        do {
            try await AICall.record(purpose: "productShot", provider: "imagePlayground", model: "imagePlayground", detail: desc.summary,
                                    sink: { [context] r in context?.insert(AIRequestLog(r)); try? context?.save() }) {
                let url = try await presentSheet()
                defer { try? FileManager.default.removeItem(at: url) }
                try await processor.saveProductPhoto(from: url, for: id)
                item.productDescriptorData = try? JSONEncoder().encode(desc)
            }
            try? context?.save()
            NotificationCenter.default.post(name: .itemImagesChanged, object: id)
            return .saved
        } catch is ProductShotCancelled { return .cancelled } catch { return fail(describe(error)) }
    }

    /// "Make a product photo after saving": one sheet per saved item, in order (the user taps Use or Cancel each time). Stops on a failure.
    func makeQueued(_ ids: [UUID], context: ModelContext) async {
        self.context = context
        for id in ids {
            guard let item = try? context.fetch(FetchDescriptor<Item>(predicate: #Predicate { $0.id == id })).first else { continue }
            if case .failed = await make(for: item) { break }
        }
    }

    /// Developer flow: a neutral mid-grey plain garment of `shape`, no source image, saved as the shape's template.
    func makeTemplate(_ shape: TemplateShape) async -> Outcome {
        guard !isBusy else { return .failed("Another product photo is in progress.") }
        isBusy = true; overlay = .preparing; errorMessage = nil
        defer { isBusy = false; overlay = .idle }
        sourceImage = nil; swatch = nil
        sentence = ProductShotPrompt.templateSentence(for: shape); prompt = sentence; shortConcepts = [sentence]; title = shape.label
        do {
            try await AICall.record(purpose: "productTemplate", provider: "imagePlayground", model: "imagePlayground", detail: shape.rawValue,
                                    sink: { [context] r in context?.insert(AIRequestLog(r)); try? context?.save() }) {
                let url = try await presentSheet()
                defer { try? FileManager.default.removeItem(at: url) }
                guard let img = ImageCodec.decode(try Data(contentsOf: url)), let jpeg = ImageCodec.jpegData(img, quality: 0.92) else { throw ProcessingError.unreadableImage }
                try templates.save(jpeg, for: shape)
            }
            return .saved
        } catch is ProductShotCancelled { return .cancelled } catch { return fail(describe(error)) }
    }

    private func fail(_ message: String) -> Outcome { errorMessage = message; return .failed(message) }

    private func presentSheet() async throws -> URL {
        try await withCheckedThrowingContinuation { c in waiting = c; overlay = .sheet; isPresented = true }
    }

    private func askSleeve() async -> Sleeve? {
        await withCheckedContinuation { c in sleeveAnswer = c; askingSleeve = true }
    }

    /// The one-tap "Sleeve?" answer; nil = dismissed.
    func answerSleeve(_ s: Sleeve?) {
        askingSleeve = false
        guard let c = sleeveAnswer else { return }
        sleeveAnswer = nil; c.resume(returning: s)
    }

    /// The sheet's "Use": the file is copied out of Apple's temporary location straight away.
    func deliver(_ url: URL) {
        guard let c = waiting else { return }
        waiting = nil; isPresented = false; overlay = .saving
        let copy = FileManager.default.temporaryDirectory.appendingPathComponent("productshot-\(UUID().uuidString).\(url.pathExtension)")
        do { try FileManager.default.copyItem(at: url, to: copy); c.resume(returning: copy) } catch { c.resume(throwing: error) }
    }

    /// The sheet's "Cancel" (or a swipe down).
    func cancel() {
        isPresented = false
        guard let c = waiting else { return }
        waiting = nil; c.resume(throwing: ProductShotCancelled())
    }

    /// Deletes only product.jpg; the descriptor stays so the next one is made from the same description.
    static func removeProductPhoto(_ item: Item, store: ImageStore) {
        store.removeProductPhoto(for: item.id)
        NotificationCenter.default.post(name: .itemImagesChanged, object: item.id)
    }

    static func hasProduct(_ item: Item, store: ImageStore) -> Bool { hasProduct(item.id, store: store) }
    static func hasProduct(_ id: UUID, store: ImageStore) -> Bool {
        FileManager.default.fileExists(atPath: store.url(for: ImageStore.productName, id: id).path)
    }

    private static func onWhite(_ image: CGImage) -> CGImage {
        guard let ctx = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return image }
        ctx.setFillColor(red: 1, green: 1, blue: 1, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: image.width, height: image.height))
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return ctx.makeImage() ?? image
    }
}
