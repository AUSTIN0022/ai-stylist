import CoreGraphics
import Foundation
import Testing
@testable import StyleEngine

@Suite("S4 card layout") struct CardLayoutTests {
    let canvas = CGSize(width: 300, height: 375)
    let square = CGSize(width: 100, height: 100)

    func inside(_ r: CGRect) -> Bool { r.minX >= 0 && r.minY >= 0 && r.maxX <= canvas.width + 0.001 && r.maxY <= canvas.height + 0.001 }

    @Test("S4-U12 slot boxes: top above bottom, footwear below, inside the card") func u12() {
        let l = CardLayout.layout([.top: square, .bottom: square, .footwear: square], canvas: canvas)
        let (t, b, f) = (l[.top]!, l[.bottom]!, l[.footwear]!)
        #expect(t.midY < b.midY && b.midY < f.midY)
        #expect(t.minY < b.minY && f.minY > b.minY)
        #expect(t.width >= f.width)                    // top largest, footwear smaller
        for r in l.values { #expect(inside(r)) }
    }
    @Test("S4-U13 aspect fit keeps proportions inside the box") func u13() {
        let tall = CGSize(width: 50, height: 400), wide = CGSize(width: 400, height: 50)
        let a = CardLayout.layout([.top: tall, .bottom: wide], canvas: canvas)
        #expect(abs(a[.top]!.width / a[.top]!.height - 0.125) < 0.001)
        #expect(abs(a[.bottom]!.width / a[.bottom]!.height - 8) < 0.001)
        for r in a.values { #expect(inside(r)) }
        #expect(CardLayout.box(.top, in: canvas, slots: [.top, .bottom]).insetBy(dx: -0.01, dy: -0.01).contains(a[.top]!))
        #expect(CardLayout.box(.bottom, in: canvas, slots: [.top, .bottom]).insetBy(dx: -0.01, dy: -0.01).contains(a[.bottom]!))
    }
    @Test("S4-U14 one-piece takes the top and bottom area") func u14() {
        let two = CardLayout.layout([.top: square, .bottom: square], canvas: canvas)
        let one = CardLayout.layout([.onePiece: CGSize(width: 100, height: 200), .footwear: square], canvas: canvas)
        let dress = one[.onePiece]!
        #expect(dress.height > two[.top]!.height)
        #expect(dress.minY <= two[.top]!.minY + 1 && dress.maxY >= two[.bottom]!.maxY - 1)
        #expect(one[.footwear]!.minY >= dress.maxY - 1)
    }
    @Test("S4-U15 sets, outerwear left, accessories right, at most two") func u15() {
        let l = CardLayout.layout([.setTop: square, .setBottom: square, .setDrape: square, .footwear: square,
                                   .outerwear: square, .accessory1: square, .accessory2: square], canvas: canvas)
        let plain = CardLayout.layout([.top: square, .bottom: square, .footwear: square, .outerwear: square], canvas: canvas)
        #expect(l[.setTop]!.minY < l[.setBottom]!.minY)
        #expect(l[.setTop]!.midX == l[.setBottom]!.midX)
        #expect(l[.outerwear]!.maxX <= l[.setTop]!.minX + 1 && l[.outerwear]!.midX < canvas.width / 2)
        #expect(l[.accessory1]!.minX >= l[.setTop]!.maxX - 1 && l[.accessory2]!.minX >= l[.setTop]!.maxX - 1)
        #expect(l[.accessory1]!.midY < l[.accessory2]!.midY)
        #expect(plain[.outerwear]!.maxX <= plain[.top]!.minX + 1)
        for r in l.values { #expect(inside(r)) }
        #expect(l.keys.filter { $0 == .accessory1 || $0 == .accessory2 }.count == 2)
    }
    @Test("zero-size images fall back to the box") func zero() {
        let l = CardLayout.layout([.top: .zero], canvas: canvas)
        #expect(l[.top]!.width > 0 && inside(l[.top]!))
    }
}
