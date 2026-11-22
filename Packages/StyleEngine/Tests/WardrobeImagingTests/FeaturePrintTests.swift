import CoreGraphics
import Foundation
import Testing
@testable import WardrobeImaging

// S6-I03 (Mac version): real Vision feature prints. The same picture matches itself; a different picture is further away.

@Suite("S6 feature print") struct FeaturePrintTests {
    func stripes(_ a: String, _ b: String) -> CGImage {
        makeImage(256, 256) { ctx in
            fill(ctx, a, 0, 0, 256, 256)
            for k in stride(from: 0, to: 256, by: 32) { fill(ctx, b, k, 0, 16, 256) }
        }
    }

    @Test("a print is made, and the same image is at distance ~0") func same() throws {
        let img = stripes("C04020", "202020")
        let p1 = try #require(FeaturePrint.compute(from: img)), p2 = try #require(FeaturePrint.compute(from: img))
        let d = try #require(FeaturePrint.distance(p1, p2))
        #expect(d < 0.01)
    }

    @Test("a very different image is further away than the same one") func different() throws {
        let a = try #require(FeaturePrint.compute(from: stripes("C04020", "202020")))
        let b = try #require(FeaturePrint.compute(from: checkerboard()))
        let same = try #require(FeaturePrint.distance(a, a)), other = try #require(FeaturePrint.distance(a, b))
        #expect(other > same + 0.2)
    }

    @Test("garbage data gives no distance") func garbage() throws {
        let a = try #require(FeaturePrint.compute(from: solid("336699")))
        #expect(FeaturePrint.distance(a, Data([1, 2, 3])) == nil)
    }
}
