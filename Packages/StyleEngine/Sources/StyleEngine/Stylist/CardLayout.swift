import CoreGraphics
import Foundation

// Sprint 4: where each cut-out sits on an outfit card. Pure: slots with image sizes and a canvas in, rectangles out.

public enum CardLayout {
    private static let leftSlots: [Slot] = [.outerwear, .baseLayer, .setDrape]

    /// The box a slot may use, in canvas points. `slots` decides whether the side columns exist.
    public static func box(_ slot: Slot, in canvas: CGSize, slots: Set<Slot>) -> CGRect {
        let hasLeft = !slots.isDisjoint(with: leftSlots), hasRight = !slots.isDisjoint(with: [.accessory1, .accessory2])
        let x0 = hasLeft ? 0.27 : 0.08, x1 = hasRight ? 0.73 : 0.92       // main column, fractions of width
        func r(_ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double) -> CGRect {
            CGRect(x: x0 * canvas.width, y: y0 * canvas.height, width: (x1 - x0) * canvas.width, height: (y1 - y0) * canvas.height)
        }
        let mid = (x0 + x1) / 2, shoeHalf = (x1 - x0) * 0.3
        switch slot {
        case .top, .setTop: return r(x0, 0.03, x1, 0.50)
        case .bottom, .setBottom: return r(x0, 0.44, x1, 0.80)
        case .onePiece: return r(x0, 0.03, x1, 0.80)
        case .footwear: return r(mid - shoeHalf, 0.81, mid + shoeHalf, 0.98)
        case .outerwear, .baseLayer, .setDrape:
            let n = Double(leftSlots.filter(slots.contains).firstIndex(of: slot) ?? 0)
            return r(0.02, 0.06 + n * 0.30, 0.25, 0.34 + n * 0.30)
        case .accessory1, .accessory2:
            let n: Double = slot == .accessory1 ? 0 : 1
            return r(0.75, 0.06 + n * 0.30, 0.98, 0.34 + n * 0.30)
        }
    }

    /// `slots`: each present slot with its image size (only the aspect matters). Each image is fitted inside its box, centred.
    public static func layout(_ slots: [Slot: CGSize], canvas: CGSize) -> [Slot: CGRect] {
        let keys = Set(slots.keys)
        var out: [Slot: CGRect] = [:]
        for (slot, size) in slots {
            let b = box(slot, in: canvas, slots: keys)
            let s = size.width > 0 && size.height > 0 ? size : CGSize(width: 1, height: 1)
            let k = min(b.width / s.width, b.height / s.height)
            let (w, h) = (s.width * k, s.height * k)
            out[slot] = CGRect(x: b.midX - w / 2, y: b.midY - h / 2, width: w, height: h)
        }
        return out
    }
}
