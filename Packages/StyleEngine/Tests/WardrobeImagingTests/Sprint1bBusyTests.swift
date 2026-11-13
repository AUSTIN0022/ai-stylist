import CoreGraphics
import Testing
@testable import WardrobeImaging

private let m = rectMask(100, 100, x: 18, y: 18, rw: 64, rh: 64)

/// Checkerboard only where `inside`/`outside` say so; flat grey elsewhere.
private func image(checkerInside: Bool, checkerOutside: Bool) -> CGImage {
    makeImage(256, 256) { ctx in
        fill(ctx, "808080", 0, 0, 256, 256)
        for y in 0..<32 { for x in 0..<32 where (x + y) % 2 == 0 {
            let inMask = x >= 6 && x < 26 && y >= 6 && y < 26
            if inMask ? checkerInside : checkerOutside { fill(ctx, "000000", x * 8, y * 8, 8, 8) }
        } }
    }
}
@Test func S1B_U21_plainSurroundNoFlag() {
    #expect(QualityCheck.measure(image: image(checkerInside: false, checkerOutside: false), mask: m).busyEdgeDensity < 0.02)
}
@Test func S1B_U22_checkerSurroundFlagged() {
    #expect(QualityCheck.check(image: image(checkerInside: true, checkerOutside: true), mask: m) == .busyBackground)
}
@Test func S1B_U23_patternOnlyInsideMask() {
    #expect(QualityCheck.check(image: image(checkerInside: true, checkerOutside: false), mask: m) == .ok)
}
