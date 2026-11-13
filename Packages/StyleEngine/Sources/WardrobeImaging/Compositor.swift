import CoreGraphics

/// Cut-out rendering and the white display image.
public enum Compositor {
    /// Transparent image cropped to the mask bounds plus `margin` pixels. The mask must match the image size.
    public static func cutout(of image: CGImage, mask: Mask, margin: Int) -> CGImage? {
        guard mask.width == image.width, mask.height == image.height, let b = mask.bounds else { return nil }
        let src = PixelBuffer(image)
        let x0 = Int(b.minX) - margin, y0 = Int(b.minY) - margin
        let w = Int(b.width) + 2 * margin, h = Int(b.height) + 2 * margin
        var out = [UInt8](repeating: 0, count: w * h * 4)
        for y in 0..<h { for x in 0..<w {
            let sx = x0 + x, sy = y0 + y
            guard sx >= 0, sy >= 0, sx < src.width, sy < src.height, mask.pixels[sy * mask.width + sx] > 127 else { continue }
            let i = (sy * src.width + sx) * 4, o = (y * w + x) * 4
            out[o] = src.data[i]; out[o + 1] = src.data[i + 1]; out[o + 2] = src.data[i + 2]; out[o + 3] = src.data[i + 3]
        } }
        return PixelBuffer(width: w, height: h, data: out).makeImage()
    }

    /// Cut-out centred on a white square, with a small margin around the longer side.
    public static func display(from cutout: CGImage, side: Int = 1024) -> CGImage {
        let inner = Double(side) * 0.88
        let scale = min(inner / Double(cutout.width), inner / Double(cutout.height))
        let w = Double(cutout.width) * scale, h = Double(cutout.height) * scale
        return draw(side: side) { ctx in
            ctx.draw(cutout, in: CGRect(x: (Double(side) - w) / 2, y: (Double(side) - h) / 2, width: w, height: h))
        }
    }

    /// Fallback when there is no cut-out: the original, centre-cropped to a square.
    public static func centerCropSquare(_ image: CGImage, side: Int = 1024) -> CGImage {
        let s = min(image.width, image.height)
        let crop = CGRect(x: (image.width - s) / 2, y: (image.height - s) / 2, width: s, height: s)
        guard let cropped = image.cropping(to: crop) else { return image }
        return draw(side: side) { $0.draw(cropped, in: CGRect(x: 0, y: 0, width: side, height: side)) }
    }

    /// Scaled so the longer side is at most `maxSide`.
    public static func downscaled(_ image: CGImage, maxSide: Int) -> CGImage {
        guard max(image.width, image.height) > maxSide else { return image }
        return PixelBuffer(image, maxSide: maxSide).makeImage() ?? image
    }

    static func flattenedOnWhite(_ image: CGImage) -> CGImage {
        draw(width: image.width, height: image.height) { $0.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height)) }
    }

    private static func draw(side: Int, _ body: (CGContext) -> Void) -> CGImage { draw(width: side, height: side, body) }

    private static func draw(width: Int, height: Int, _ body: (CGContext) -> Void) -> CGImage {
        let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: sRGBSpace,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(colorSpace: sRGBSpace, components: [1, 1, 1, 1])!)
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        ctx.interpolationQuality = .high
        body(ctx)
        return ctx.makeImage()!
    }
}
