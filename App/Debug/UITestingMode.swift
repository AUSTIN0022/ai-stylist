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

    /// Five ready items: two tops, two bottoms, one pair of shoes.
    @MainActor static func seed(_ c: ModelContext) {
        func add(_ name: String, _ cat: StyleEngine.Category, _ sub: Subcategory, _ colour: ColorName) {
            let i = Item(originalFile: "", cutoutFile: nil, displayFile: "")
            var t = ItemTags(); t.category = cat; t.subcategory = sub; t.styleOrigin = .western; t.pattern = .solid
            t.dressCodes = [.smartCasual]; t.formality = 3; t.seasons = [.summer, .monsoon, .winter]; t.warmth = 1; t.statement = .plain
            if cat == .footwear { t.closedToe = true }
            i.aiRawData = try? JSONEncoder().encode(t); i.name = name; i.colorNames = [colour.rawValue]; i.status = .ready
            c.insert(i)
        }
        add("Rust shirt", .top, .shirt, .rust); add("Cream shirt", .top, .shirt, .cream)
        add("Black chinos", .bottom, .chinos, .black); add("Navy trousers", .bottom, .trousers, .navy)
        add("White sneakers", .footwear, .sneakers, .white)
        try? c.save()
    }
}
#endif
