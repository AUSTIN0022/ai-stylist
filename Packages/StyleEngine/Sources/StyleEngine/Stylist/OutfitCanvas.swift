import CoreGraphics
import Foundation

// Sprint 5: the outfit builder's state. Plain data: every gesture ends in one of these calls.

/// One item on the canvas. x, y are the item's centre as fractions of the canvas, so a layout looks the same on any screen.
public struct PlacedItem: Codable, Equatable, Sendable {
    public var itemId: UUID
    public var x: Double, y: Double
    public var scale: Double
    public var z: Int
}

public struct OutfitCanvas: Codable, Equatable, Sendable {
    public private(set) var items: [PlacedItem] = []

    public static let scaleRange: ClosedRange<Double> = 0.3...2.5
    /// An item at scale 1 is this fraction of the canvas wide and tall (the image is fitted inside).
    public static let baseSize = 0.4

    public init() {}

    /// An AI or saved outfit opened in the builder: each item at its card-layout position.
    public init(slots: [Slot: UUID]) {
        for (slot, id) in slots.sorted(by: { $0.key < $1.key }) { put(id, slot: slot, present: Set(slots.keys)) }
    }

    public func point(of id: UUID, in canvas: CGSize) -> CGPoint? {
        items.first { $0.itemId == id }.map { CGPoint(x: $0.x * canvas.width, y: $0.y * canvas.height) }
    }

    /// Places (or moves) an item with its centre at a point in canvas points.
    public mutating func place(_ id: UUID, at p: CGPoint, in canvas: CGSize) {
        let (x, y) = (canvas.width > 0 ? p.x / canvas.width : 0.5, canvas.height > 0 ? p.y / canvas.height : 0.5)
        if items.contains(where: { $0.itemId == id }) { moveTo(id, x: x, y: y); return }
        items.append(PlacedItem(itemId: id, x: 0, y: 0, scale: 1, z: (items.map(\.z).max() ?? -1) + 1))
        moveTo(id, x: x, y: y)
    }

    /// Tap-to-add: the item goes to its slot's card position. An item already there is not added twice;
    /// one that would share its slot (a second bottom, a third top) is replaced.
    public mutating func add(_ item: EngineItem, using wardrobe: [EngineItem]) {
        guard !items.contains(where: { $0.itemId == item.id }) else { return }
        let byId = Dictionary(wardrobe.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let current = items.compactMap { byId[$0.itemId] }
        let slots = OutfitSlots.infer([item] + current)
        items.removeAll { byId[$0.itemId] != nil && slots[$0.itemId] == nil }
        put(item.id, slot: slots[item.id] ?? .top, present: Set(slots.values))
    }

    private mutating func put(_ id: UUID, slot: Slot, present: Set<Slot>) {
        let box = CardLayout.box(slot, in: CGSize(width: 1, height: 1), slots: present)
        let scale = min(box.width, box.height) / Self.baseSize
        items.append(PlacedItem(itemId: id, x: box.midX, y: box.midY,
                                scale: min(max(scale, Self.scaleRange.lowerBound), Self.scaleRange.upperBound),
                                z: (items.map(\.z).max() ?? -1) + 1))
    }

    /// Moves to a centre in fractions, clamped so at least a third of the item stays on the canvas.
    public mutating func moveTo(_ id: UUID, x: Double, y: Double) {
        guard let n = items.firstIndex(where: { $0.itemId == id }) else { return }
        let half = Self.baseSize * items[n].scale / 2
        func clamp(_ v: Double) -> Double { min(max(v, -half / 3), 1 + half / 3) }
        items[n].x = clamp(x); items[n].y = clamp(y)
    }

    /// Drag: translation in canvas points.
    public mutating func move(_ id: UUID, by d: CGSize, in canvas: CGSize) {
        guard let p = items.first(where: { $0.itemId == id }), canvas.width > 0, canvas.height > 0 else { return }
        moveTo(id, x: p.x + d.width / canvas.width, y: p.y + d.height / canvas.height)
    }

    public mutating func scale(_ id: UUID, to s: Double) {
        guard let n = items.firstIndex(where: { $0.itemId == id }) else { return }
        items[n].scale = min(max(s, Self.scaleRange.lowerBound), Self.scaleRange.upperBound)
        moveTo(id, x: items[n].x, y: items[n].y)
    }

    public mutating func bringToFront(_ id: UUID) {
        guard let n = items.firstIndex(where: { $0.itemId == id }) else { return }
        items[n].z = (items.map(\.z).max() ?? 0) + 1
    }

    public mutating func sendToBack(_ id: UUID) {
        guard let n = items.firstIndex(where: { $0.itemId == id }) else { return }
        items[n].z = (items.map(\.z).min() ?? 0) - 1
    }

    /// Takes the item off the canvas; the wardrobe item is untouched.
    public mutating func remove(_ id: UUID) { items.removeAll { $0.itemId == id } }

    /// Back to front, for drawing.
    public var drawOrder: [PlacedItem] { items.sorted { $0.z < $1.z } }
}

/// Which outfit slot each hand-picked item fills. Earlier items win a contested slot; items with no slot left get none.
public enum OutfitSlots {
    private static let outerSubs: Set<Subcategory> = [.jacket, .blazer, .hoodie]
    private static let roleSlot: [SetRole: Slot] = [
        .kurta: .setTop, .blouse: .setTop, .choli: .setTop, .kurtaBottom: .setBottom, .lehengaSkirt: .setBottom,
        .dupatta: .setDrape, .saree: .setDrape,
    ]

    public static func infer(_ items: [EngineItem]) -> [UUID: Slot] {
        var out: [UUID: Slot] = [:], used = Set<Slot>()
        func take(_ i: EngineItem, _ options: [Slot]) {
            if let s = options.first(where: { !used.contains($0) }) { out[i.id] = s; used.insert(s) }
        }
        var tops: [EngineItem] = []
        for i in items {
            let t = i.tags
            if i.setGroupId != nil {
                let s = roleSlot[t.setRole ?? .none] ?? (t.category == .top ? .setTop : t.category == .bottom ? .setBottom : .setDrape)
                take(i, [s]); continue
            }
            if t.category == .outerwear || outerSubs.contains(t.subcategory ?? .other) { take(i, [.outerwear]); continue }
            switch t.category {
            case .top: tops.append(i)
            case .bottom: take(i, [.bottom])
            case .onePiece: take(i, [.onePiece])
            case .footwear: take(i, [.footwear])
            case .accessory: take(i, [.accessory1, .accessory2])
            default: break
            }
        }
        // Two tops: a plain tee goes under the other one.
        let ordered = tops.count == 2 && tops[0].tags.subcategory == .tshirt && tops[1].tags.subcategory != .tshirt ? tops.reversed() : tops
        for t in ordered { take(t, [.top, .baseLayer]) }
        return out
    }
}
