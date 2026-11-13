import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Decode (with EXIF orientation applied once, here), encode, and downsampled thumbnails. ImageIO only.
public enum ImageCodec {
    /// Upright CGImage. `maxPixel` nil keeps full resolution.
    public static func decode(_ data: Data, maxPixel: Int? = nil) -> CGImage? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return upright(src, maxPixel)
    }

    public static func thumbnail(at url: URL, maxPixel: Int) -> CGImage? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return upright(src, maxPixel)
    }

    private static func upright(_ src: CGImageSource, _ maxPixel: Int?) -> CGImage? {
        guard let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? Int, let h = props[kCGImagePropertyPixelHeight] as? Int else { return nil }
        let target = min(max(w, h), maxPixel ?? max(w, h))
        return CGImageSourceCreateThumbnailAtIndex(src, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: target,
        ] as CFDictionary)
    }

    public static func jpegData(_ image: CGImage, quality: Double = 0.9) -> Data? {
        // JPEG has no alpha: flatten onto white first.
        let flat = Compositor.flattenedOnWhite(image)
        return encode(flat, UTType.jpeg, [kCGImageDestinationLossyCompressionQuality: quality])
    }

    public static func pngData(_ image: CGImage) -> Data? { encode(image, UTType.png, [:]) }

    private static func encode(_ image: CGImage, _ type: UTType, _ options: [CFString: Any]) -> Data? {
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(out, type.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, image, options as CFDictionary)
        return CGImageDestinationFinalize(dest) ? out as Data : nil
    }
}
