import CoreGraphics
import Foundation
import StyleEngine
import WardrobeImaging

/// Still photo of a label -> blur check on the box area -> text passes (still, 2x box crop, contrast-stretched, inverted), merged with the live lines -> parse.
/// Closures are injectable so tests never touch Vision.
struct LabelPipeline: Sendable {
    static let blurryMessage = "Hold steady, it's blurry"
    enum Outcome { case read(LabelData, jpeg: Data), blurry, unreadable }

    var scan: @Sendable (CGImage) async throws -> (text: String, barcode: String?) = LabelScanner.scan
    var isBlurry: @Sendable (CGImage, CGRect?) -> Bool = { QualityCheck.isBlurry($0, region: $1) }

    func run(photo: Data, box: CGRect?, liveLines: [String], liveBarcode: String?, pastBrands: [String]) async -> Outcome {
        guard let img = ImageCodec.decode(photo, maxPixel: 2048), let jpeg = ImageCodec.jpegData(img, quality: 0.9) else { return .unreadable }
        if isBlurry(img, box) { return .blurry }
        let still = (try? await scan(img)) ?? (text: "", barcode: nil)
        // More looks: the box at 2x (a lone size letter), then the same view contrast-stretched (faint print on white)
        // and inverted (white on dark). Each line is kept once.
        func split(_ t: String) -> [String] { t.split(whereSeparator: \.isNewline).map(String.init) }
        let base = box.flatMap { LabelScanner.upscaledCrop(img, box: $0) } ?? img
        var passes = [split(still.text)]
        if base !== img { passes.append(split((try? await scan(base))?.text ?? "")) }
        for variant in [LabelScanner.contrastStretched(base), LabelScanner.inverted(base)] {
            if let v = variant { passes.append(split((try? await scan(v))?.text ?? "")) }
        }
        let lines = LabelParser.mergeLines(live: liveLines, passes: passes)
        let data = LabelParser.parse(text: lines.joined(separator: "\n"), barcode: still.barcode ?? liveBarcode, pastBrands: pastBrands)
        return .read(data, jpeg: jpeg)
    }
}
