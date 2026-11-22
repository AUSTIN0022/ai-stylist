import StyleEngine

/// Which questions the review asks about a page, and the answers it offers. Pure functions over a `Photo`
/// (the rules that need no `Photo` live in the StyleEngine package: `ColorName.choices`, `ItemTags.needsCheck`).
enum ReviewQuestions {
    static func askColor(_ p: ReviewModel.Photo) -> Bool { p.processed?.colorAmbiguous.first == true && !p.colorDone }
    /// Ask whenever neither the AI nor the user has given a category.
    static func askCategory(_ p: ReviewModel.Photo) -> Bool { p.processed != nil && effectiveCategory(p) == nil }
    static func effectiveCategory(_ p: ReviewModel.Photo) -> Category? { p.overrides.category ?? p.ai?.category }
    /// The kind of item, but only when it belongs to the category in force (the AI's "shirt" is no answer for a page added under Bottoms).
    static func effectiveSubcategory(_ p: ReviewModel.Photo) -> Subcategory? {
        guard let s = p.overrides.subcategory ?? p.ai?.subcategory else { return nil }
        guard let c = effectiveCategory(p) else { return s }
        return subcategories(for: c).contains(s) ? s : nil
    }
    /// A category added from a category page still needs a kind that fits it before Save (the AI named none that fits, or no AI ran).
    static func needsSubcategory(_ p: ReviewModel.Photo) -> Bool {
        guard p.presetCategory != nil, p.processed != nil, effectiveCategory(p) != nil else { return false }
        return effectiveSubcategory(p) == nil
    }
    /// The cross-check: the AI named another category than the page it was added under.
    static func categoryNote(_ p: ReviewModel.Photo) -> String? {
        guard let preset = p.presetCategory, let ai = p.ai, ai.category != preset else { return nil }
        return "The AI thinks this is a \(ai.category.displayName.lowercased()) (\(ai.subcategory.displayName.lowercased())). It will be saved under \(preset.displayName) because you added it there. Pick what it is below."
    }
    /// The AI's answer as one chip plus up to two alternatives from its category; nil when there is none or the user chose "Something else".
    static func suggestion(_ p: ReviewModel.Photo) -> (title: String, alternatives: [Subcategory])? {
        guard let ai = p.ai, !p.showAllChoices else { return nil }
        return (ai.title, identityAlternatives(for: ai.subcategory, in: ai.category))
    }
    /// Only garments have a fit; never footwear or accessories (and not before the category is known).
    static func askFit(_ p: ReviewModel.Photo) -> Bool { p.processed != nil && !p.fitDone && effectiveCategory(p).map(asksFit) == true }
    /// The colour names as the item will read after Save (the user's choice replaces the first).
    static func colorNames(_ p: ReviewModel.Photo) -> [ColorName] {
        var n = p.processed?.colorNames ?? []
        if let c = p.colorAnswer, !n.isEmpty { n[0] = c }
        return n
    }
    /// The colour question's options: the current name, then the two nearest other named colours.
    static func colorChoices(_ p: ReviewModel.Photo) -> [ColorName] {
        guard let pr = p.processed, let first = pr.colorNames.first, let hex = pr.hexColors.first else { return [] }
        return ColorName.choices(first: first, hex: hex)
    }
    /// A dot on the chip. Not while the AI is still answering (`awaitingAI`: idle with a tagger present, or running).
    static func needsCheck(_ p: ReviewModel.Photo, _ f: TagField, hasTagger: Bool) -> Bool {
        if p.tagState == .running || (p.tagState == .idle && hasTagger) { return false }
        return p.effectiveTags.needsCheck(f)
    }
}
