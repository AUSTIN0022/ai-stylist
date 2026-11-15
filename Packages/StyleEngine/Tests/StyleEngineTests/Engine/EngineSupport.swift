import Foundation
import Testing
@testable import StyleEngine

let testToday = Date(timeIntervalSince1970: 1_798_000_000)
let allSeasons: [Season] = [.summer, .monsoon, .winter]

struct FixtureItem: Codable {
    let id: UUID, key: String, name: String
    let tags: ItemTags
    let colors: [ColorName]
    let setGroupId: UUID?
    let lastWornAt: Date?
    var engineItem: EngineItem {
        EngineItem(id: id, name: name, tags: tags, colors: colors, setGroupId: setGroupId, lastWornAt: lastWornAt)
    }
}

struct Fixture {
    let raw: [FixtureItem]
    var items: [EngineItem] { raw.map(\.engineItem) }
    func id(_ key: String) -> UUID { raw.first { $0.key == key }!.id }
    func item(_ key: String) -> EngineItem { raw.first { $0.key == key }!.engineItem }
    func key(of id: UUID) -> String { raw.first { $0.id == id }?.key ?? "?" }
}

func loadFixture(_ name: String = "wardrobe") throws -> Fixture {
    let url = try #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
    struct File: Codable { let items: [FixtureItem] }
    return Fixture(raw: try JSONDecoder().decode(File.self, from: Data(contentsOf: url)).items)
}

/// Tiny hand-built item. Footwear is closed-toe unless it is a sandal or slide.
func mk(_ name: String, _ cat: Category, _ sub: Subcategory, _ colors: [ColorName] = [.black],
        dc: [DressCode] = [.smartCasual], f: Int = 3, pattern: Pattern = .solid, fabric: Fabric = .cotton,
        statement: Statement = .plain, warmth: Int = 1, seasons: [Season] = allSeasons, closed: Bool? = nil,
        worn: Date? = nil, group: UUID? = nil, role: SetRole = .none, origin: StyleOrigin = .western,
        fit: Fit? = nil) -> EngineItem {
    var t = ItemTags()
    t.category = cat; t.subcategory = sub; t.styleOrigin = origin; t.setRole = role; t.pattern = pattern
    t.fabric = fabric; t.dressCodes = dc; t.formality = f; t.seasons = seasons; t.warmth = warmth
    t.statement = statement; t.fit = fit
    if cat == .footwear { t.closedToe = closed ?? !(sub == .sandals || sub == .slides) }
    return EngineItem(name: name, tags: t, colors: colors, setGroupId: group, lastWornAt: worn)
}

/// A plain top, bottom and shoes that pass any smart-casual occasion.
func basics() -> [EngineItem] {
    [mk("Top", .top, .shirt, [.white]), mk("Bottom", .bottom, .chinos, [.black]), mk("Shoes", .footwear, .sneakers, [.white])]
}

func run(_ intent: OccasionIntent, _ items: [EngineItem], _ ctx: EngineContext? = nil, count: Int = 3) -> EngineResult {
    OutfitEngine.generate(intent: intent, items: items, context: ctx ?? EngineContext(today: testToday, seed: 7), count: count)
}
func ctx(seed: UInt64 = 7, exclude: Set<OutfitKey> = [], pairs: [PairKey: Double] = [:]) -> EngineContext {
    EngineContext(today: testToday, excludeOutfits: exclude, pairWeights: pairs, seed: seed)
}

extension EngineItem {
    var cat: Category? { tags.category }
    var sub: Subcategory? { tags.subcategory }
    var isNonSolidOrStatement: Bool {
        !([Pattern.solid, .textured].contains(tags.pattern ?? .solid)) || tags.statement == .statement
    }
}

func items(of o: OutfitCandidate, in all: [EngineItem]) -> [EngineItem] {
    o.slots.values.compactMap { id in all.first { $0.id == id } }
}
func core(of o: OutfitCandidate, in all: [EngineItem]) -> [EngineItem] {
    items(of: o, in: all).filter { $0.cat != .accessory }
}
func isOpenToe(_ i: EngineItem) -> Bool {
    i.tags.closedToe == false || (i.tags.closedToe == nil && (i.sub == .sandals || i.sub == .slides))
}

// Intents used by the scenario tests and the eval.
extension OccasionIntent {
    static var diwali: OccasionIntent { .init(occasion: .festival, timeOfDay: .evening, setting: .indoor, weatherFeel: .mild) }
}
