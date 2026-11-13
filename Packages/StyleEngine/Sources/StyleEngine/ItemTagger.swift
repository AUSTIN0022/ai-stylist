import CoreGraphics
import FoundationModels

/// Call A of the tagger (Sprint 2): what the item is. Only these three fields, using the real taxonomy enums.
@Generable public struct IdentityTags: Codable, Equatable, Sendable {
    @Guide(description: "The main kind of clothing item shown")
    public var category: Category
    @Guide(description: "The specific type of item. A knitted pullover or zip knit is sweater. A collared short or long sleeve jersey top is polo.")
    public var subcategory: Subcategory
    @Guide(description: "western for everyday Western clothes; indian for kurta, saree, lehenga; indoWestern for a mix")
    public var styleOrigin: StyleOrigin

    public init(category: Category, subcategory: Subcategory, styleOrigin: StyleOrigin) {
        self.category = category; self.subcategory = subcategory; self.styleOrigin = styleOrigin
    }

    /// "T-shirt · Top"
    public var title: String { "\(subcategory.displayName) · \(category.displayName)" }
}

/// Tags an item from its cut-out in three calls (PRD 5.2): A identity, B construction (fields depend on the category), C usage.
/// `version` is saved on each item so stale items can be re-tagged (bump it when a prompt or struct changes).
/// B and C return only the fields they own, as `ItemTags`.
public protocol ItemTagger: Sendable {
    var version: String { get }
    func identity(cutout: CGImage) async throws -> IdentityTags
    func construction(cutout: CGImage, category: Category, subcategory: Subcategory) async throws -> ItemTags
    func usage(cutout: CGImage, category: Category, subcategory: Subcategory) async throws -> ItemTags
}

/// Taggers that know whether their model can run right now (nil = available). Drives the no-AI mode.
public protocol AvailabilityReporting: Sendable { var unavailableReason: String? { get } }

// MARK: Call B: one struct per category group, so the model is only asked what applies.

/// Tag fields call B asks for, per category: a subset of `fields(for:)`.
public func constructionFields(for category: Category) -> Set<TagField> {
    let asked: Set<TagField>
    switch category {
    case .top, .outerwear, .onePiece: asked = [.collar, .sleeve, .fit, .length, .fabric, .pattern]
    case .bottom: asked = [.fit, .length, .fabric, .pattern]
    case .footwear: asked = [.fabric, .closedToe]
    case .accessory: asked = [.fabric]
    }
    return asked.intersection(fields(for: category))
}

@Generable public struct TopConstruction: Codable, Equatable, Sendable {
    @Guide(description: "Fabric, best guess from the look. Use unknown if unsure.")
    public var fabric: Fabric
    @Guide(description: "Surface pattern. solid means one plain colour.")
    public var pattern: Pattern
    @Guide(description: "How loose the garment is cut")
    public var fit: Fit
    @Guide(description: "cropped, regular or long: how far the garment reaches down the body")
    public var length: Length
    @Guide(description: "Collar or neckline. mandarin is a short stand-up band with no fold. spread is a folded collar with points apart. buttonDown has points buttoned to the shirt. polo is a soft knit collar. none for items without a neckline feature.")
    public var collar: Collar
    @Guide(description: "Sleeve length. Use long for jackets, hoodies and sweaters with sleeves.")
    public var sleeve: Sleeve
    public init(fabric: Fabric, pattern: Pattern, fit: Fit, length: Length, collar: Collar, sleeve: Sleeve) {
        self.fabric = fabric; self.pattern = pattern; self.fit = fit; self.length = length; self.collar = collar; self.sleeve = sleeve
    }
    public var tags: ItemTags {
        var t = ItemTags(); t.fabric = fabric; t.pattern = pattern; t.fit = fit; t.collar = collar; t.sleeve = sleeve
        t.length = [.cropped, .regular, .long].contains(length) ? length : nil   // bottoms' values are not valid here
        return t
    }
}

@Generable public struct BottomConstruction: Codable, Equatable, Sendable {
    @Guide(description: "Fabric, best guess from the look. Use unknown if unsure.")
    public var fabric: Fabric
    @Guide(description: "Surface pattern. solid means one plain colour.")
    public var pattern: Pattern
    @Guide(description: "How loose the garment is cut")
    public var fit: Fit
    @Guide(description: "short (above the knee), ankle (ends at the ankle) or full (reaches the shoe)")
    public var length: Length
    public init(fabric: Fabric, pattern: Pattern, fit: Fit, length: Length) {
        self.fabric = fabric; self.pattern = pattern; self.fit = fit; self.length = length
    }
    public var tags: ItemTags {
        var t = ItemTags(); t.fabric = fabric; t.pattern = pattern; t.fit = fit
        t.length = [.short, .ankle, .full].contains(length) ? length : nil   // tops' values are not valid here
        return t
    }
}

@Generable public struct FootwearConstruction: Codable, Equatable, Sendable {
    @Guide(description: "Material, best guess from the look. Use unknown if unsure.")
    public var fabric: Fabric
    @Guide(description: "true if the toes are covered, false for sandals, slides and open shoes")
    public var closedToe: Bool
    public init(fabric: Fabric, closedToe: Bool) { self.fabric = fabric; self.closedToe = closedToe }
    public var tags: ItemTags { var t = ItemTags(); t.fabric = fabric; t.closedToe = closedToe; return t }
}

@Generable public struct AccessoryConstruction: Codable, Equatable, Sendable {
    @Guide(description: "Material, best guess from the look. Use unknown if unsure.")
    public var fabric: Fabric
    public init(fabric: Fabric) { self.fabric = fabric }
    public var tags: ItemTags { var t = ItemTags(); t.fabric = fabric; return t }
}

/// Keeps only the call-B fields that apply to `category` (the one place that enforces `constructionFields`).
public func construction(for category: Category, in answer: ItemTags) -> ItemTags {
    let allowed = constructionFields(for: category)
    var t = ItemTags()
    if allowed.contains(.fabric) { t.fabric = answer.fabric }
    if allowed.contains(.pattern) { t.pattern = answer.pattern }
    if allowed.contains(.fit) { t.fit = answer.fit }
    if allowed.contains(.length) { t.length = answer.length }
    if allowed.contains(.collar) { t.collar = answer.collar }
    if allowed.contains(.sleeve) { t.sleeve = answer.sleeve }
    if allowed.contains(.closedToe) { t.closedToe = answer.closedToe }
    return t
}

/// Call C: when to wear it.
@Generable public struct UsageTags: Codable, Equatable, Sendable {
    @Guide(description: "Occasions this item suits, best match first", .minimumCount(1), .maximumCount(3))
    public var dressCodes: [DressCode]
    @Guide(description: "Formality from 1 (home wear) to 5 (formal)", .range(1...5))
    public var formality: Int
    @Guide(description: "Seasons this item suits", .minimumCount(1), .maximumCount(3))
    public var seasons: [Season]
    @Guide(description: "How warm: 1 light, 2 medium, 3 warm", .range(1...3))
    public var warmth: Int
    @Guide(description: "plain for everyday basics, statement for bold or heavily decorated items, medium between")
    public var statement: Statement
    @Guide(description: "One sentence, under 20 words, describing only the garment, not the background")
    public var caption: String
    public init(dressCodes: [DressCode], formality: Int, seasons: [Season], warmth: Int, statement: Statement, caption: String) {
        self.dressCodes = dressCodes; self.formality = formality; self.seasons = seasons
        self.warmth = warmth; self.statement = statement; self.caption = caption
    }
    public var tags: ItemTags {
        var t = ItemTags()
        t.dressCodes = dressCodes; t.formality = formality; t.seasons = seasons; t.warmth = warmth; t.statement = statement; t.caption = caption
        return t
    }
}

public extension IdentityTags {
    /// The identity fields as `ItemTags`.
    var tags: ItemTags { var t = ItemTags(); t.category = category; t.subcategory = subcategory; t.styleOrigin = styleOrigin; return t }
}

public extension ItemTags {
    /// The new user-corrections blob after the user sets one field. nil, or the AI's own answer, removes the override
    /// (choosing the AI value is not a correction). An empty list is rejected (the blob comes back unchanged).
    /// This is the only place the override rule lives.
    func settingOverride<V: Equatable>(_ field: WritableKeyPath<ItemTags, V?>, to value: V?, raw: ItemTags) -> ItemTags {
        var r = self
        guard let value else { r[keyPath: field] = nil; return r }
        if let list = value as? [DressCode], list.isEmpty { return self }
        if let list = value as? [Season], list.isEmpty { return self }
        r[keyPath: field] = Self.same(value, raw[keyPath: field]) ? nil : value
        return r
    }
    private static func same<V: Equatable>(_ a: V, _ b: V?) -> Bool {
        guard let b else { return false }
        if let x = a as? [DressCode], let y = b as? [DressCode] { return Set(x) == Set(y) }
        if let x = a as? [Season], let y = b as? [Season] { return Set(x) == Set(y) }
        return a == b
    }
}

/// Taggers that can report the token count of their last call.
public protocol TokenReporting: Sendable { var lastTokenCount: Int? { get } }

/// Up to two other subcategories of `category`, in table order. Never from another category.
public func identityAlternatives(for subcategory: Subcategory, in category: Category) -> [Subcategory] {
    Array(subcategories(for: category).filter { $0 != subcategory }.prefix(2))
}
