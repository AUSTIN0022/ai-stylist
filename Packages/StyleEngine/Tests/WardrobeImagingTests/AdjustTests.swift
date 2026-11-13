import CoreGraphics
import Testing
@testable import WardrobeImaging

// S2-U42: Adjust on a camera shot. The camera box limits the automatic choice only; a part the user taps or ticks
// outside the box must still be cut out (it used to throw noSubject, so Apply silently did nothing).
private func block(_ x0: Int, _ x1: Int) -> Mask {
    var px = [UInt8](repeating: 0, count: 100 * 100)
    for y in 30..<70 { for x in x0..<x1 { px[y * 100 + x] = 255 } }
    return Mask(width: 100, height: 100, pixels: px)
}

@Test func S2_U42_choiceOutsideTheCameraBoxStillCutsOut() throws {
    let img = makeImage(100, 100) { fill($0, "B5522B", 0, 0, 100, 100) }
    let session = CutoutSession(image: img, instances: [block(10, 40), block(60, 90)], box: CGRect(x: 0, y: 0.2, width: 0.5, height: 0.6))
    let first = try session.initial()
    #expect(first.chosen == [0])
    let other = try first.recut(chosen: [1])
    #expect(other.chosen == [1] && other.mask != first.mask)
    let tapped = try first.recut(tap: CGPoint(x: 0.75, y: 0.5))
    #expect(tapped.chosen == [1])
}
