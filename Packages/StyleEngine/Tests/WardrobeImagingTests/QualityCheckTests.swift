import CoreGraphics
import Testing
@testable import WardrobeImaging

/// Sharp detail only inside the centred mask, flat grey around it (a checkerboard surround now counts as busy, S1B).
private func sharpInsidePlainOutside() -> CGImage {
    makeImage(256, 256) { ctx in
        fill(ctx, "808080", 0, 0, 256, 256)
        for y in 6..<26 { for x in 6..<26 where (x + y) % 2 == 0 { fill(ctx, "000000", x * 8, y * 8, 8, 8) } }
    }
}

private let centred = rectMask(100, 100, x: 18, y: 18, rw: 64, rh: 64)   // 41% of the frame

@Test func S1_U14_tooDark() {
    #expect(QualityCheck.check(image: solid("000000", 256, 256), mask: centred) == .tooDark)
}

@Test func S1_U15_blurry() {
    let sharp = checkerboard()
    #expect(QualityCheck.check(image: sharpInsidePlainOutside(), mask: centred) == .ok)
    #expect(QualityCheck.check(image: blurred(sharp), mask: centred) == .blurry)
}

@Test func S1_U16_noClearItem() {
    let sharp = checkerboard()
    #expect(QualityCheck.check(image: sharp, mask: rectMask(100, 100, x: 40, y: 40, rw: 17, rh: 17)) == .noClearItem)  // 2.9%
    #expect(QualityCheck.check(image: sharp, mask: nil) == .noClearItem)
}

@Test func S1_U17_itemCutOff() {
    let sharp = checkerboard()
    #expect(QualityCheck.check(image: sharp, mask: rectMask(100, 100, x: 0, y: 50, rw: 50, rh: 50)) == .cutOff)   // left + bottom
    #expect(QualityCheck.check(image: sharp, mask: rectMask(100, 100, x: 0, y: 25, rw: 50, rh: 50)) != .cutOff)  // left only (a checkerboard surround is now "busy", so not == .ok)
}

@Test func S1_U18_goodPhoto() {
    #expect(QualityCheck.check(image: sharpInsidePlainOutside(), mask: centred) == .ok)
}

@Test func S1_U19_orderOfReasons() {
    // A black image is dark and has no edges (blurry): the first reason wins.
    #expect(QualityCheck.check(image: solid("000000", 256, 256), mask: nil) == .tooDark)
}

// Extra (round 2, label scanner): blur is judged on the box area only.
@Test func S1B_U49_blurOnRegion() {
    // Sharp checkerboard in the left half, flat grey right half.
    let img = makeImage(256, 256) { ctx in
        fill(ctx, "808080", 0, 0, 256, 256)
        for y in 0..<32 { for x in 0..<16 where (x + y) % 2 == 0 { fill(ctx, "000000", x * 8, y * 8, 8, 8) } }
    }
    #expect(!QualityCheck.isBlurry(img, region: CGRect(x: 0, y: 0, width: 0.5, height: 1)))
    #expect(QualityCheck.isBlurry(img, region: CGRect(x: 0.5, y: 0, width: 0.5, height: 1)))
    #expect(QualityCheck.isBlurry(blurred(checkerboard()), region: nil))
}
