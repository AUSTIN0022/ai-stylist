import CoreGraphics
import CoreImage
import Foundation
import Testing
import StyleEngine
@testable import WardrobeImaging

/// Not a gate: writes before/after PNGs for eyeballing to /private/tmp/claude-catalogue-shots/.
/// Real photos: put jpgs in the folder named by CATALOGUE_PHOTOS (cut out with Vision, macOS). A synthetic tilted tee is always written.
@Test func catalogueProofShots() async throws {
    let out = URL(fileURLWithPath: "/private/tmp/claude-catalogue-shots/")
    try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
    func save(_ name: String, _ img: CGImage) throws { try ImageCodec.pngData(img)!.write(to: out.appendingPathComponent(name + ".png")) }

    func shoot(_ name: String, work: CGImage, result: CutoutResult, category: StyleEngine.Category?) throws {
        let t0 = ContinuousClock.now
        let after = Catalogue.render(cutout: result.cutout, original: work, mask: result.mask, category: category)
        print(name, "render ms", (ContinuousClock.now - t0) / .milliseconds(1))
        try save(name + "_original", Compositor.downscaled(work, maxSide: 1000))
        try save(name + "_before", Compositor.display(from: result.cutout, side: 1024))
        try save(name + "_after", after)
    }

    // Synthetic: navy tee flat-lay, 12 deg crooked, blue-cast photo, on a warm desk.
    let desk = "B89A78"
    let work = makeImage(1600, 1200) { ctx in
        fill(ctx, desk, 0, 0, 1600, 1200)
        ctx.translateBy(x: 800, y: 600); ctx.rotate(by: 12 * .pi / 180)
        ctx.setFillColor(rgb("22305A"))
        ctx.fill(CGRect(x: -230, y: -300, width: 460, height: 620))        // body
        ctx.fill(CGRect(x: -400, y: -300, width: 800, height: 170))        // sleeves
        ctx.setFillColor(rgb(desk)); ctx.fillEllipse(in: CGRect(x: -70, y: -330, width: 140, height: 120))   // neckline
    }
    let ci = CIImage(cgImage: work).applyingFilter("CIColorMatrix", parameters: ["inputRVector": CIVector(x: 0.85, y: 0, z: 0, w: 0), "inputBVector": CIVector(x: 0, y: 0, z: 1.12, w: 0)])
    let tinted = CIContext().createCGImage(ci, from: ci.extent, format: .RGBA8, colorSpace: sRGB)!
    // Mask: everything that is not desk-coloured in the untinted drawing.
    let p = PixelBuffer(work)
    var m = [UInt8](repeating: 0, count: p.width * p.height)
    for i in 0..<m.count where abs(Int(p.data[i * 4]) - 0xB8) > 30 { m[i] = 255 }
    let mask = Mask(width: p.width, height: p.height, pixels: m)
    let cut = try #require(Compositor.cutout(of: tinted, mask: mask.eroded(by: 1), margin: 20))
    try shoot("synthetic_tee", work: tinted, result: CutoutResult(cutout: cut, mask: mask.resized(maxSide: 256)), category: .top)

    if let dir = ProcessInfo.processInfo.environment["CATALOGUE_PHOTOS"] {
        let names = ((try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? []).filter { $0.hasSuffix(".jpg") }.map { String($0.dropLast(4)) }.sorted()
        for (name, cat) in names.map({ ($0, Optional<StyleEngine.Category>.none) }) {
            guard let data = FileManager.default.contents(atPath: dir + "/" + name + ".jpg"), let full = ImageCodec.decode(data) else { continue }
            let w = Compositor.downscaled(full, maxSide: 2048)
            try shoot(name, work: w, result: try await VisionCutoutService().cutout(from: w, box: nil), category: cat)
        }
    }
}
