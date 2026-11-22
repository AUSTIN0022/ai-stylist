#if DEBUG
import CoreGraphics
import Foundation
import StyleEngine
import SwiftData
import WardrobeImaging

/// `-uiTesting` launch argument (XCUITest only): an in-memory store with a small seeded wardrobe, a temporary image folder and an
/// AI provider that is always unavailable. No photos, no model, no network: the UI tests drive plain app flows.
enum UITestingMode {
    static var isOn: Bool { ProcessInfo.processInfo.arguments.contains("-uiTesting") }
    static let provider = UnavailableProvider()
    static let store = ImageStore(root: FileManager.default.temporaryDirectory.appendingPathComponent("uitesting-\(UUID().uuidString)"))

    struct UnavailableProvider: AIProvider {
        let name = "uitesting"
        let unavailableReason: String? = "UI testing: no AI."
        func makeTagger() -> any ItemTagger { Tagger() }
        func makeIntentParser() -> any IntentParser { Parser() }
        func makeNoteWriter() -> any NoteWriter { Writer() }
        struct Tagger: ItemTagger {
            let version = "uitesting"
            func identity(cutout: CGImage) async throws -> IdentityTags { throw AIUnavailable(reason: "UI testing") }
            func construction(cutout: CGImage, category: StyleEngine.Category, subcategory: Subcategory) async throws -> ItemTags { throw AIUnavailable(reason: "UI testing") }
            func usage(cutout: CGImage, category: StyleEngine.Category, subcategory: Subcategory) async throws -> ItemTags { throw AIUnavailable(reason: "UI testing") }
        }
        struct Parser: IntentParser {
            let version = "uitesting"
            func parse(message: String, previous: OccasionIntent?, recent: [String]) async throws -> OccasionIntent { throw AIUnavailable(reason: "UI testing") }
        }
        struct Writer: NoteWriter {
            let version = "uitesting"
            func notes(prompt: String, count: Int) async throws -> [String] { throw AIUnavailable(reason: "UI testing") }
        }
    }

    /// A solid garment-shaped PNG with a transparent margin, so cards and the builder have real pixels to draw and tap.
    private static func garmentPNG(_ hex: UInt32) -> Data? {
        guard let ctx = CGContext(data: nil, width: 200, height: 260, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.setFillColor(red: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255, blue: CGFloat(hex & 255) / 255, alpha: 1)
        ctx.fill(CGRect(x: 20, y: 20, width: 160, height: 220))
        return ctx.makeImage().flatMap { ImageCodec.pngData($0) }
    }

    /// Five ready items (two tops, two bottoms, shoes) with cut-out files, and three saved outfits built from them.
    @MainActor static func seed(_ c: ModelContext) {
        var made: [String: Item] = [:]
        func add(_ name: String, _ cat: StyleEngine.Category, _ sub: Subcategory, _ colour: ColorName) {
            let i = Item(originalFile: "", cutoutFile: ImageStore.cutoutName, displayFile: "")
            if let png = garmentPNG(UInt32(abs(name.hashValue) % 0xFFFFFF)) { try? store.save(png, named: ImageStore.cutoutName, for: i.id) }
            made[name] = i
            var t = ItemTags(); t.category = cat; t.subcategory = sub; t.styleOrigin = .western; t.pattern = .solid
            t.dressCodes = [.smartCasual]; t.formality = 3; t.seasons = [.summer, .monsoon, .winter]; t.warmth = 1; t.statement = .plain
            if cat == .footwear { t.closedToe = true }
            i.aiRawData = try? JSONEncoder().encode(t); i.name = name; i.colorNames = [colour.rawValue]; i.status = .ready
            c.insert(i)
        }
        add("Rust shirt", .top, .shirt, .rust); add("Cream shirt", .top, .shirt, .cream)
        add("Black chinos", .bottom, .chinos, .black); add("Navy trousers", .bottom, .trousers, .navy)
        add("White sneakers", .footwear, .sneakers, .white)
        let outfits: [(name: String, top: String, bottom: String)] = [
            ("Outfit one", "Rust shirt", "Black chinos"), ("Outfit two", "Cream shirt", "Black chinos"), ("Outfit three", "Rust shirt", "Navy trousers"),
        ]
        for (n, spec) in outfits.enumerated() {
            let o = Outfit(name: spec.name, source: .ai); o.saved = true; o.createdAt = Date(timeIntervalSinceNow: Double(-n))
            c.insert(o)
            for (slot, item) in [("top", spec.top), ("bottom", spec.bottom), ("footwear", "White sneakers")] {
                if let it = made[item] { c.insert(OutfitItem(outfitId: o.id, itemId: it.id, slot: slot)) }
            }
        }
        try? c.save()
    }
}
#endif
