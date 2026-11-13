import CoreGraphics
import Testing
@testable import WardrobeImaging

// S2-U50...U53: Adjust cut-out box, zoom and pan. Pure geometry plus a re-cut on stored masks (no Vision).
private func bar(_ x0: Int, _ x1: Int) -> Mask {
    var px = [UInt8](repeating: 0, count: 100 * 100)
    for y in 30..<70 { for x in x0..<x1 { px[y * 100 + x] = 255 } }
    return Mask(width: 100, height: 100, pixels: px)
}
private func session() -> CutoutSession {
    CutoutSession(image: solid("B5522B"), instances: [bar(10, 90), bar(93, 99)], box: nil)
}

@Test func S2_U50_recutBoxKeepsInstancesCentredInsideAndClipsTheMask() throws {
    let first = try session().initial()
    let r = try first.recut(box: CGRect(x: 0, y: 0.2, width: 0.6, height: 0.6))
    #expect(r.chosen == [0])                                    // the sliver centred outside is dropped
    let b = try #require(r.mask.bounds)
    #expect(Double(b.maxX) / Double(r.mask.width) <= 0.70)       // box 0.6 + 10% of its width = 0.66, not 0.9
    #expect(r.mask != first.mask)
    // a box around the sliver picks the sliver
    #expect(try first.recut(box: CGRect(x: 0.9, y: 0.2, width: 0.1, height: 0.6)).chosen == [1])
}

@Test func S2_U51_boxWithNoInstanceCentreThrowsAndLeavesCutoutUnchanged() throws {
    let first = try session().initial()
    let before = first.chosen
    do { _ = try first.recut(box: CGRect(x: 0.7, y: 0.0, width: 0.15, height: 0.2)); Issue.record("should throw") }
    catch { #expect(error as? CutoutError == .noItemInBox) }
    #expect(first.chosen == before)
    // a fake result has no stored masks
    let fake = CutoutResult(cutout: solid("FFFFFF"), mask: bar(10, 20))
    #expect(throws: CutoutError.self) { try fake.recut(box: CGRect(x: 0, y: 0, width: 1, height: 1)) }
}

@Test func S2_U52_selectionBoxGeometry() {
    let m = SelectionBox.minSide
    #expect(m == 0.08)
    var b = SelectionBox(CGRect(x: 0.2, y: 0.2, width: 0.4, height: 0.4))
    b.dragCorner(.bottomRight, to: CGPoint(x: 0.8, y: 0.9))                  // opposite corner stays
    func near(_ r: CGRect, _ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double) -> Bool {
        abs(r.minX - x0) < 1e-9 && abs(r.minY - y0) < 1e-9 && abs(r.maxX - x1) < 1e-9 && abs(r.maxY - y1) < 1e-9
    }
    #expect(near(b.rect, 0.2, 0.2, 0.8, 0.9))
    b.dragCorner(.topLeft, to: CGPoint(x: -0.5, y: 0.1))                     // clamped to the photo
    #expect(near(b.rect, 0, 0.1, 0.8, 0.9))
    b.dragCorner(.topLeft, to: CGPoint(x: 0.95, y: 0.95))                    // cannot cross: minimum side
    #expect(near(b.rect, 0.8 - m, 0.9 - m, 0.8, 0.9))
    var c = SelectionBox(CGRect(x: 0.2, y: 0.2, width: 0.4, height: 0.4))
    c.dragCentre(by: CGSize(width: 0.1, height: -0.05))
    #expect(abs(c.rect.minX - 0.3) < 1e-9 && abs(c.rect.minY - 0.15) < 1e-9 && c.rect.size == CGSize(width: 0.4, height: 0.4))
    c.dragCentre(by: CGSize(width: 5, height: 5))                            // stops at the photo edge, size kept
    #expect(abs(c.rect.maxX - 1) < 1e-9 && abs(c.rect.maxY - 1) < 1e-9 && abs(c.rect.width - 0.4) < 1e-9)
    #expect(SelectionBox(CGRect(x: 0.5, y: 0.5, width: 0.01, height: 2)).rect.width == m)   // init normalises
}

@Test func S2_U53_viewToPhotoMappingIsStableUnderZoomAndPan() {
    let fit = CGRect(x: 0, y: 100, width: 300, height: 400)
    var v = PhotoViewport(container: CGSize(width: 300, height: 600), fit: fit)
    let p = CGPoint(x: 0.3, y: 0.7)
    let at1 = v.viewPoint(forPhoto: p)
    #expect(at1 == CGPoint(x: 90, y: 380))
    #expect(v.photoPoint(forView: at1) == p)
    v.setScale(2.5); v.setPan(CGSize(width: -120, height: 60))
    let at25 = v.viewPoint(forPhoto: p)
    #expect(at25 != at1)
    let back = v.photoPoint(forView: at25)
    #expect(abs(back.x - p.x) < 1e-9 && abs(back.y - p.y) < 1e-9)           // same normalised point as at 1x
    v.setScale(9); #expect(v.scale == 5)
    v.setScale(0.2); #expect(v.scale == 1 && v.pan == .zero)                  // 1x cannot be panned
    v.setScale(2); v.setPan(CGSize(width: 9999, height: 9999))
    let tl = v.viewPoint(forPhoto: .zero)                                     // photo edge never leaves the left of the view
    #expect(tl.x <= 0.0001)
}
