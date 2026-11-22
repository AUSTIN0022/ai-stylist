import Foundation

// Sprint 5: "these are one set". Roles come from category and subcategory; the engine then treats the group as one unit.

public struct SetLinkError: Error, Equatable, Sendable { public let reason: String }

public enum SetLink {
    public static func roles(for items: [EngineItem]) -> Result<[UUID: SetRole], SetLinkError> {
        guard items.count >= 2 else { return .failure(.init(reason: "Pick at least two items to make a set.")) }
        var out: [UUID: SetRole] = [:]
        var slots: [String: String] = [:]    // top / bottom / drape → item name, one each
        for i in items {
            let t = i.tags
            let role: SetRole, part: String
            switch (t.category, t.subcategory) {
            case (_, .saree): (role, part) = (.saree, "drape")
            case (_, .dupatta): (role, part) = (.dupatta, "drape")
            case (.top, .blouse): (role, part) = (.blouse, "top")
            case (.top, .choli): (role, part) = (.choli, "top")
            case (.top, _): (role, part) = (.kurta, "top")
            case (.bottom, .lehengaSkirt): (role, part) = (.lehengaSkirt, "bottom")
            case (.bottom, _): (role, part) = (.kurtaBottom, "bottom")
            default: return .failure(.init(reason: "\(i.name.isEmpty ? "This item" : i.name) can't be part of a set: only a top, a bottom and a saree or dupatta can."))
            }
            if let other = slots[part] { return .failure(.init(reason: "A set has one \(part): \(other) and \(i.name) are both \(part)s.")) }
            slots[part] = i.name; out[i.id] = role
        }
        return .success(out)
    }
}
