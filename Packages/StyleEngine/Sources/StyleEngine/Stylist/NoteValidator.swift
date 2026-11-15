import Foundation

// Sprint 4: a note may only mention subcategories and colours that are in its outfit; otherwise it is dropped.

public enum NoteValidator {
    /// Words in `note` that name an item type or colour the outfit does not have. Empty means valid.
    public static func offences(_ note: String, for items: [EngineItem]) -> [String] {
        var text = " " + note.lowercased().replacingOccurrences(of: "dress code", with: "") + " "
        for (k, v) in ["gray": "grey", "t-shirt": "tshirt", " tee ": " tshirt "] { text = text.replacingOccurrences(of: k, with: v) }
        let words = Set(text.split(whereSeparator: { !$0.isLetter }).map(String.init))
        func has(_ name: String) -> Bool { words.contains(name) || words.contains(name + "s") || words.contains(name + "es") }
        let subs = Set(items.compactMap(\.tags.subcategory)), colours = Set(items.flatMap(\.colors))
        var bad: [String] = []
        for s in Subcategory.allCases where s != .other && !subs.contains(s) && has(s.rawValue.lowercased()) { bad.append(s.rawValue.lowercased()) }
        // Longest colour names first ("light blue"), so "blue" does not fire inside them.
        var rest = " " + text.split(whereSeparator: { !$0.isLetter }).joined(separator: " ") + " "
        for c in ColorName.allCases.sorted(by: { $0.displayName.count > $1.displayName.count }) where c != .multicolor {
            let n = " " + c.displayName.lowercased() + " "
            if rest.contains(n) {
                rest = rest.replacingOccurrences(of: n, with: " ")
                if !colours.contains(c) { bad.append(c.displayName.lowercased()) }
            }
        }
        return bad
    }

    public static func isValid(_ note: String, for items: [EngineItem]) -> Bool { offences(note, for: items).isEmpty }
}

/// Text-only input for the note call: the intent in one line, then a numbered row list per outfit.
public enum NotePrompt {
    public static func text(intent: OccasionIntent, outfits: [[(Slot, EngineItem)]]) -> String {
        let head = [intent.occasion.rawValue.spaced, intent.timeOfDay.rawValue, intent.setting.rawValue,
                    intent.weatherFeel == .unknown ? nil : intent.weatherFeel.rawValue].compactMap { $0 }.joined(separator: ", ")
        var out = "Occasion: \(head)\n"
        for (n, o) in outfits.enumerated() {
            out += "\nOutfit \(n + 1).\n"
            for (slot, item) in o {
                let tags = [item.colors.first?.rawValue.lowercased(), item.tags.fit?.rawValue].compactMap { $0 }.joined(separator: ", ")
                out += "\(slot.rawValue): \(item.name) (\(tags))\n"
            }
        }
        return out
    }
}

private extension String {
    var spaced: String {
        var s = ""
        for ch in self { if ch.isUppercase { s += " " + ch.lowercased() } else { s.append(ch) } }
        return s.prefix(1).uppercased() + s.dropFirst()
    }
}
