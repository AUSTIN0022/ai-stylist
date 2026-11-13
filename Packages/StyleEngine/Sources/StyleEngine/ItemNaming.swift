import Foundation

/// "[first colour] [collar if notable] [fabric if known] [subcategory]": "Rust mandarin-collar linen shirt".
public enum ItemNaming {
    public static func autoName(color: ColorName?, tags: ItemTags) -> String {
        var words: [String] = []
        if let color { words.append(color.displayName.lowercased()) }
        // Notable collars only; a fit word stands in for bottoms ("relaxed chinos").
        switch tags.collar {
        case .mandarin: words.append("mandarin-collar")
        case .camp: words.append("camp-collar")
        case .vNeck: words.append("v-neck")
        default: break
        }
        if let fit = tags.fit, fit != .regular, let s = tags.subcategory, subcategories(for: .bottom).contains(s) {
            words.append(fit.displayName.lowercased())
        }
        if let f = tags.fabric, f != .unknown { words.append(f == .cottonLinen ? "cotton-linen" : f.displayName.lowercased()) }
        words.append(tags.subcategory?.displayName.lowercased() ?? "item")
        let s = words.joined(separator: " ")
        return s.prefix(1).uppercased() + s.dropFirst()
    }
}
