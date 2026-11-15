import Foundation

/// The garment shapes that get one canonical template image each (Image Playground copies the layout of its source image,
/// so a fixed template gives every product photo the same, straight shape).
public enum TemplateShape: String, CaseIterable, Codable, Sendable {
    case tshirtShort, tshirtLong, shirt, hoodie, jacket, trousers, shorts, shoes

    /// File name without extension, in the app bundle and in Application Support/templates.
    public var fileName: String {
        switch self {
        case .tshirtShort: "tshirt-short"
        case .tshirtLong: "tshirt-long"
        default: rawValue
        }
    }
    public var label: String {
        switch self {
        case .tshirtShort: "T-shirt, short sleeve"
        case .tshirtLong: "T-shirt / sweater, long sleeve"
        case .shirt: "Shirt"
        case .hoodie: "Hoodie"
        case .jacket: "Jacket / blazer"
        case .trousers: "Trousers / jeans / chinos"
        case .shorts: "Shorts"
        case .shoes: "Shoes"
        }
    }
}

/// Pure rules: which template shape an item maps to, and whether its photo is generated from the template or from its own cut-out.
public enum ProductTemplate {
    public enum Source: Equatable, Sendable { case template(TemplateShape), cutout }

    /// nil for garments with no template yet (kurta, saree, dress, accessories...).
    public static func shape(for tags: ItemTags) -> TemplateShape? {
        if tags.category == .footwear { return .shoes }
        switch tags.subcategory {
        case .tshirt?, .polo?: return tags.sleeve == .long ? .tshirtLong : .tshirtShort
        case .sweater?: return .tshirtLong
        case .shirt?: return .shirt
        case .hoodie?: return .hoodie
        case .jacket?, .blazer?: return .jacket
        case .jeans?, .chinos?, .trousers?: return .trousers
        case .shorts?: return .shorts
        default: return nil
        }
    }

    /// Template only when one exists for the shape and the garment is plain (solid, textured or untagged): a template would lose a print.
    public static func source(for tags: ItemTags, available: Set<TemplateShape>) -> Source {
        guard let shape = shape(for: tags), available.contains(shape) else { return .cutout }
        switch tags.pattern {
        case nil, .solid?, .textured?: return .template(shape)
        default: return .cutout
        }
    }
}
