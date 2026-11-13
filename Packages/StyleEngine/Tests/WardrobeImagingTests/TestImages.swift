import CoreGraphics
import CoreImage
import Foundation
import ImageIO
import StyleEngine
import UniformTypeIdentifiers
@testable import WardrobeImaging

typealias Category = StyleEngine.Category

let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

/// Draw into a new sRGB RGBA image. Coordinates in `draw` are top-left based (flipped for you).
func makeImage(_ w: Int, _ h: Int, _ draw: (CGContext) -> Void) -> CGImage {
    let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: sRGB,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.translateBy(x: 0, y: CGFloat(h)); ctx.scaleBy(x: 1, y: -1)
    draw(ctx)
    return ctx.makeImage()!
}

func rgb(_ hex: String) -> CGColor {
    let v = UInt32(hex, radix: 16)!
    return CGColor(colorSpace: sRGB, components: [CGFloat((v >> 16) & 255) / 255, CGFloat((v >> 8) & 255) / 255, CGFloat(v & 255) / 255, 1])!
}

func fill(_ ctx: CGContext, _ hex: String, _ x: Int, _ y: Int, _ w: Int, _ h: Int) {
    ctx.setFillColor(rgb(hex)); ctx.fill(CGRect(x: x, y: y, width: w, height: h))
}

func solid(_ hex: String, _ w: Int = 100, _ h: Int = 100) -> CGImage {
    makeImage(w, h) { fill($0, hex, 0, 0, w, h) }
}

func checkerboard(_ size: Int = 256, cell: Int = 8) -> CGImage {
    makeImage(size, size) { ctx in
        fill(ctx, "FFFFFF", 0, 0, size, size)
        for y in 0..<(size / cell) { for x in 0..<(size / cell) where (x + y) % 2 == 0 { fill(ctx, "000000", x * cell, y * cell, cell, cell) } }
    }
}

func blurred(_ image: CGImage, radius: Double = 14) -> CGImage {
    let ci = CIImage(cgImage: image).clampedToExtent().applyingGaussianBlur(sigma: radius).cropped(to: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    return CIContext().createCGImage(ci, from: ci.extent, format: .RGBA8, colorSpace: sRGB)!
}

/// Rectangle mask, row 0 = top.
func rectMask(_ w: Int, _ h: Int, x: Int, y: Int, rw: Int, rh: Int) -> Mask {
    var px = [UInt8](repeating: 0, count: w * h)
    for j in y..<min(h, y + rh) { for i in x..<min(w, x + rw) { px[j * w + i] = 255 } }
    return Mask(width: w, height: h, pixels: px)
}

func jpeg(_ image: CGImage) -> Data { ImageCodec.jpegData(image, quality: 0.9)! }

func tempRoot() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("wardrobe-test-\(UUID().uuidString)")
}

func hexDistance(_ a: String, _ b: String) -> Int {
    let x = UInt32(a, radix: 16)!, y = UInt32(b, radix: 16)!
    return [16, 8, 0].map { abs(Int((x >> $0) & 255) - Int((y >> $0) & 255)) }.max()!
}
