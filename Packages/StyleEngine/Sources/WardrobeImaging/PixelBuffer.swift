import CoreGraphics

let sRGBSpace = CGColorSpace(name: CGColorSpace.sRGB)!

/// RGBA8 premultiplied sRGB pixels, row 0 = top. Everything in this module reads pixels through this.
struct PixelBuffer {
    let width: Int, height: Int
    var data: [UInt8]

    /// Draws `image` into an sRGB buffer, scaled down so its longer side is at most `maxSide` (never scaled up).
    init(_ image: CGImage, maxSide: Int? = nil) {
        var w = image.width, h = image.height
        if let m = maxSide, max(w, h) > m {
            let s = Double(m) / Double(max(w, h))
            w = max(1, Int((Double(w) * s).rounded())); h = max(1, Int((Double(h) * s).rounded()))
        }
        width = w; height = h
        var d = [UInt8](repeating: 0, count: w * h * 4)
        d.withUnsafeMutableBytes { p in
            let ctx = CGContext(data: p.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                space: sRGBSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            ctx.interpolationQuality = .high
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        }
        data = d
    }

    init(width: Int, height: Int, data: [UInt8]) { self.width = width; self.height = height; self.data = data }

    func rgba(_ x: Int, _ y: Int) -> (UInt8, UInt8, UInt8, UInt8) {
        let i = (y * width + x) * 4
        return (data[i], data[i + 1], data[i + 2], data[i + 3])
    }

    func makeImage() -> CGImage? {
        var d = data
        return d.withUnsafeMutableBytes { p in
            CGContext(data: p.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                      space: sRGBSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)?.makeImage()
        }
    }
}
