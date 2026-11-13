import Foundation

/// Wardrobe filters and search. AND across fields, OR within a field; empty field = no constraint.
/// Works on snapshots whose `tags` are the effective (merged) tags.
public struct WardrobeFilter: Equatable, Sendable {
    public struct Snapshot: Sendable {
        public var id: UUID
        public var name: String
        public var caption: String
        public var tags: ItemTags
        public var colourNames: [String]   // ColorName raw values
        public var brand: String?
        public var subBrand: String?
        public init(id: UUID, name: String, caption: String, tags: ItemTags, colourNames: [String], brand: String?, subBrand: String?) {
            self.id = id; self.name = name; self.caption = caption; self.tags = tags
            self.colourNames = colourNames; self.brand = brand; self.subBrand = subBrand
        }
    }

    public var categories: Set<Category> = []
    public var colours: Set<String> = []        // ColorName raw values
    public var dressCodes: Set<DressCode> = []
    public var seasons: Set<Season> = []
    public var brands: Set<String> = []
    public var text = ""

    public init() {}

    public var isActive: Bool {
        !(categories.isEmpty && colours.isEmpty && dressCodes.isEmpty && seasons.isEmpty && brands.isEmpty
          && text.trimmingCharacters(in: .whitespaces).isEmpty)
    }

    public mutating func clear() { self = WardrobeFilter() }

    public func matches(_ s: Snapshot) -> Bool {
        if !categories.isEmpty, !(s.tags.category.map(categories.contains) ?? false) { return false }
        if !colours.isEmpty, colours.isDisjoint(with: s.colourNames) { return false }
        if !dressCodes.isEmpty, dressCodes.isDisjoint(with: s.tags.dressCodes ?? []) { return false }
        if !seasons.isEmpty, seasons.isDisjoint(with: s.tags.seasons ?? []) { return false }
        if !brands.isEmpty, !(s.brand.map(brands.contains) ?? false) { return false }
        let q = text.trimmingCharacters(in: .whitespaces)
        if q.isEmpty { return true }
        var hay = [s.name, s.caption, s.brand ?? "", s.subBrand ?? "", s.tags.subcategory?.displayName ?? ""]
        for c in s.colourNames { hay.append(c); hay.append(ColorName(rawValue: c)?.displayName ?? c) }
        return hay.contains { $0.localizedCaseInsensitiveContains(q) }
    }

    public func apply(to items: [Snapshot]) -> [Snapshot] { items.filter(matches) }
}
