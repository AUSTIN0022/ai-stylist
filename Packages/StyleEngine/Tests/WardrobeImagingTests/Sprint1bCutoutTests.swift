import CoreGraphics
import Testing
@testable import WardrobeImaging

private func sel(_ m: [Mask], box: CGRect? = nil) -> SubjectSelector.Selection { SubjectSelector.select(m, box: box) }
private func r(_ x: Int, _ y: Int, _ w: Int, _ h: Int) -> Mask { rectMask(100, 100, x: x, y: y, rw: w, rh: h) }

@Test func S1B_U07_bedTouchingEdgesLoses() {
    let s = sel([r(0, 0, 100, 60), r(30, 30, 40, 30)])
    #expect(s.chosen == [1] && !s.needsChoice)
}
@Test func S1B_U08_thumbnailDropped() {
    let s = sel([r(20, 15, 60, 70), r(85, 2, 12, 10)])
    #expect(s.chosen == [0] && !s.needsChoice)
}
@Test func S1B_U09_twinShoes() {
    let s = sel([r(15, 35, 30, 30), r(55, 35, 30, 30)])
    #expect(s.chosen == [0, 1] && !s.needsChoice)
}
@Test func S1B_U10_equalFarApartNeedsChoice() {
    let s = sel([r(5, 5, 25, 25), r(70, 70, 25, 25)])
    #expect(s.needsChoice)
    #expect(s.chosen.count == 1)
}
@Test func S1B_U11_single() {
    let s = sel([r(30, 30, 40, 40)])
    #expect(s.chosen == [0] && !s.needsChoice && s.candidates.count == 1)
    #expect(s.candidates[0].areaShare == 0.16)
}
@Test func S1B_U12_tapInsideInstance() {
    let m = [r(5, 5, 20, 20), r(40, 40, 20, 20), r(70, 70, 20, 20)]
    #expect(SubjectSelector.select(m, tap: CGPoint(x: 0.8, y: 0.8)) == [2])
}
@Test func S1B_U13_tapOutsideNearest() {
    let m = [r(5, 5, 20, 20), r(40, 40, 20, 20), r(70, 70, 20, 20)]
    #expect(SubjectSelector.select(m, tap: CGPoint(x: 0.95, y: 0.5)) == [2])
    #expect(SubjectSelector.select(m, tap: CGPoint(x: 0.02, y: 0.3)) == [0])
}
private func session(_ m: [Mask], box: CGRect? = nil) -> CutoutSession {
    CutoutSession(image: makeImage(100, 100) { fill($0, "B5522B", 0, 0, 100, 100) }, instances: m, box: box)
}
@Test func S1B_U14_explicitIndicesUnion() throws {
    let m = [r(5, 5, 20, 20), r(40, 40, 20, 20), r(70, 70, 20, 20)]
    let first = try session(m).initial()
    let out = try first.recut(chosen: [0, 2])
    #expect(out.chosen == [0, 2])
    #expect(out.mask == Mask.union([m[0], m[2]]))
    #expect(out.candidates == first.candidates)
}
@Test func S1B_U15_printInsideMerged() {
    let s = sel([r(20, 20, 60, 60), r(40, 40, 10, 10)])
    #expect(s.chosen == [0, 1])
}
@Test func S1B_U16_instanceOutsideBoxDropped() {
    let box = CGRect(x: 0.1, y: 0.1, width: 0.5, height: 0.5)
    let s = sel([r(20, 20, 20, 20), r(70, 70, 20, 20)], box: box)
    #expect(s.chosen == [0] && !s.needsChoice)
}
@Test func S1B_U17_maskClippedToGrownBox() throws {
    let box = CGRect(x: 0.3, y: 0.3, width: 0.4, height: 0.4)   // grown by 0.04 per side: 26...74
    let out = try session([r(0, 0, 60, 60)], box: box).initial()
    #expect(out.mask.bounds == CGRect(x: 26, y: 26, width: 34, height: 34))   // instance ends at 60
    let big = try session([r(10, 10, 80, 80)], box: box).initial()
    #expect(big.mask.bounds == CGRect(x: 26, y: 26, width: 48, height: 48))
}
@Test func S1B_U18_nothingInBox() {
    let box = CGRect(x: 0.1, y: 0.1, width: 0.3, height: 0.3)
    #expect(sel([r(60, 60, 30, 30)], box: box).noClearItem)
    #expect(throws: CutoutError.noItemInBox) { try session([r(60, 60, 30, 30)], box: box).initial() }
    #expect(SubjectSelector.boxHint == "Put the item inside the box")
}
@Test func S1B_U19_noBoxNoClip() throws {
    let m = [r(0, 10, 20, 20), r(40, 40, 30, 30)]      // second is nearer the centre, not a twin
    let out = try session(m).initial()
    #expect(out.chosen == [1])
    #expect(out.mask == m[1])
}
@Test func S1B_U20_boxScreenToPhoto() {
    // 3:4 photo (3000x4000) in a 390x845 preview, aspect fill: scale 0.21125, shown 633.75 wide, offset x -121.875.
    let guide = CGRect(x: 39, y: 200, width: 331.5, height: 442)
    let p = CameraBox.photoRect(forGuide: guide, preview: CGSize(width: 390, height: 845), photo: CGSize(width: 3000, height: 4000))
    #expect(abs(p.minX - 0.2538) < 0.001 && abs(p.minY - 0.2367) < 0.001)
    #expect(abs(p.width - 0.5230) < 0.001 && abs(p.height - 0.5231) < 0.001)
}
