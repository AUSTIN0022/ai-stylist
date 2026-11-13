import CoreGraphics
import Vision

/// On-device text + barcode read of one label photo. The text goes to `LabelParser.parse`.
public enum LabelScanner {
    public static func scan(_ image: CGImage) async throws -> (text: String, barcode: String?) {
        var text = RecognizeTextRequest()
        text.recognitionLevel = .accurate
        text.usesLanguageCorrection = false   // sizes and codes are not words
        text.minimumTextHeightFraction = 0.005   // small print and a lone size letter; the default drops tiny text
        let lines = try await text.perform(on: image).map { $0.transcript }
        let codes = (try? await DetectBarcodesRequest().perform(on: image)) ?? []
        return (lines.joined(separator: "\n"), codes.compactMap(\.payloadString).first)
    }
}

public extension LabelScanner {
    /// The box region (normalised, top-left origin) padded 5%, redrawn at 2x with smooth interpolation: a second look at tiny print.
    static func upscaledCrop(_ image: CGImage, box: CGRect) -> CGImage? {
        let w = Double(image.width), h = Double(image.height)
        let r = box.insetBy(dx: -box.width * 0.05, dy: -box.height * 0.05)
        let rect = CGRect(x: r.minX * w, y: r.minY * h, width: r.width * w, height: r.height * h).integral
            .intersection(CGRect(x: 0, y: 0, width: w, height: h))
        guard !rect.isEmpty, let crop = image.cropping(to: rect),
              let ctx = CGContext(data: nil, width: crop.width * 2, height: crop.height * 2, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.interpolationQuality = .high
        ctx.draw(crop, in: CGRect(x: 0, y: 0, width: crop.width * 2, height: crop.height * 2))
        return ctx.makeImage()
    }
}

public extension LabelScanner {
    /// Grey image with the 2nd to 98th percentile of luminance stretched to 0...255: faint print on white fabric becomes legible.
    static func contrastStretched(_ image: CGImage) -> CGImage? {
        remapped(image) { lum in
            var hist = [Int](repeating: 0, count: 256)
            lum.forEach { hist[Int($0)] += 1 }
            func percentile(_ p: Double) -> Int { var acc = 0; for v in 0..<256 { acc += hist[v]; if Double(acc) >= p * Double(lum.count) { return v } }; return 255 }
            let lo = percentile(0.02), hi = max(percentile(0.98), lo + 1)
            return { v in UInt8(max(0, min(255, (Int(v) - lo) * 255 / (hi - lo)))) }
        }
    }

    /// Grey image with light and dark swapped (white-on-dark labels).
    static func inverted(_ image: CGImage) -> CGImage? { remapped(image) { _ in { 255 - $0 } } }

    private static func remapped(_ image: CGImage, _ makeMap: ([UInt8]) -> (UInt8) -> UInt8) -> CGImage? {
        var buf = PixelBuffer(image)
        let lum = (0..<buf.width * buf.height).map { i -> UInt8 in
            UInt8((0.2126 * Double(buf.data[i * 4]) + 0.7152 * Double(buf.data[i * 4 + 1]) + 0.0722 * Double(buf.data[i * 4 + 2])).rounded())
        }
        let map = makeMap(lum)
        for (i, v) in lum.enumerated() { let o = map(v); buf.data[i * 4] = o; buf.data[i * 4 + 1] = o; buf.data[i * 4 + 2] = o; buf.data[i * 4 + 3] = 255 }
        return buf.makeImage()
    }
}
