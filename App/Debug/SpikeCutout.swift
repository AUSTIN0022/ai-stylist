import UIKit
import Vision
import CoreImage

enum SpikeCutoutError: Error { case noSubject, render }

enum SpikeImage {
    /// Redraw upright (bakes in EXIF orientation) with the long side capped at `longSide`.
    static func upright(_ image: UIImage, longSide: CGFloat) -> CGImage? {
        let s = min(1, longSide / max(image.size.width, image.size.height))
        let size = CGSize(width: image.size.width * s, height: image.size.height * s)
        let f = UIGraphicsImageRendererFormat(); f.scale = 1; f.opaque = true
        return UIGraphicsImageRenderer(size: size, format: f).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }.cgImage
    }

    /// Composite a transparent cut-out on white, long side capped at `longSide` (never upscaled).
    static func onWhite(_ cg: CGImage, longSide: CGFloat) -> CGImage? {
        let w = CGFloat(cg.width), h = CGFloat(cg.height), s = min(1, longSide / max(w, h))
        let size = CGSize(width: (w * s).rounded(), height: (h * s).rounded())
        let f = UIGraphicsImageRendererFormat(); f.scale = 1; f.opaque = true
        return UIGraphicsImageRenderer(size: size, format: f).image { ctx in
            UIColor.white.setFill(); ctx.fill(CGRect(origin: .zero, size: size))
            UIImage(cgImage: cg).draw(in: CGRect(origin: .zero, size: size))
        }.cgImage
    }
}

/// Vision foreground instance mask: all instances merged, cropped to the subject, transparent background.
func spikeCutout(_ image: CGImage) async throws -> CGImage {
    let handler = ImageRequestHandler(image)
    guard let obs = try await handler.perform(GenerateForegroundInstanceMaskRequest()),
          !obs.allInstances.isEmpty else { throw SpikeCutoutError.noSubject }
    let buffer = try obs.generateMaskedImage(for: obs.allInstances, imageFrom: handler, croppedToInstancesExtent: true)
    let ci = CIImage(cvPixelBuffer: buffer)
    guard let out = CIContext().createCGImage(ci, from: ci.extent, format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)) else {
        throw SpikeCutoutError.render
    }
    return out
}
