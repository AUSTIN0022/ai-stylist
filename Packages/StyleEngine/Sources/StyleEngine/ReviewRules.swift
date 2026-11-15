/// Pure rules behind the review questions (no UI, no Apple frameworks): which colours to offer, which tag chips need a check.
extension ColorName {
    /// The colour question's options: `first` (the extracted name), then the two nearest other named colours to `hex` ("RRGGBB").
    public static func choices(first: ColorName, hex: String) -> [ColorName] {
        // ponytail: plain RGB distance, not Lab; only orders the two suggestions, "Other" lists everything.
        func rgb(_ h: String) -> [Double] { let v = UInt32(h, radix: 16) ?? 0; return [Double((v >> 16) & 255), Double((v >> 8) & 255), Double(v & 255)] }
        func dist(_ a: [Double], _ b: [Double]) -> Double { zip(a, b).reduce(0) { $0 + ($1.0 - $1.1) * ($1.0 - $1.1) } }
        let me = rgb(hex)
        let near = allCases.filter { $0 != first && $0 != .multicolor && $0.referenceHex != nil }
            .sorted { dist(rgb($0.referenceHex!), me) < dist(rgb($1.referenceHex!), me) }
        return [first] + near.prefix(2)
    }
}

extension ItemTags {
    /// A dot on the chip: the field is empty, or fabric is `unknown`.
    public func needsCheck(_ f: TagField) -> Bool {
        switch f {
        case .fabric: fabric == nil || fabric == .unknown
        case .subcategory: subcategory == nil
        case .styleOrigin: styleOrigin == nil
        case .pattern: pattern == nil
        case .fit: fit == nil
        case .length: length == nil
        case .collar: collar == nil
        case .sleeve: sleeve == nil
        case .dressCodes: dressCodes?.isEmpty ?? true
        case .formality: formality == nil
        case .seasons: seasons == nil
        case .warmth: warmth == nil
        case .statement: statement == nil
        case .closedToe: closedToe == nil
        case .setRole: false
        }
    }
}
