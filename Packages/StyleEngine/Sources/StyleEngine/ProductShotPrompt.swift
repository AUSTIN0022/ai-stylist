import Foundation

/// Fixed prompt templates for store-style product photos (Sprint 2, Image Playground). One template per garment shape so every
/// piece comes out the same way. Pure and deterministic; brand names are never used (only the label's fabric is read).
public enum ProductShotPrompt {
    static let maxLength = 300

    /// `hexes` are the item's stored colours (same order as `colours`, no "#"); `swatch` adds the "match the reference swatch" sentence.
    /// Over 300 characters, words are dropped lowest priority first: long wording ("centred", "no mannequin, no hanger", "beside the body"),
    /// label composition, pattern word, the long swatch sentence, the hex, then the shadow. 
    /// The colour name, garment shape, sleeves, background and "no person" always stay.
    public static func make(for tags: ItemTags, colours: [ColorName], hexes: [String] = [], label: LabelData?, swatch: Bool = true) -> String {
        var out = ""
        for level in 0...6 {
            out = build(tags, colours, hexes, label, swatch, level)
            if out.count <= maxLength { break }
        }
        return out
    }

    /// "deep navy (#1F2A44)", "off-white (#EDEBE4)": the colour name with a lightness qualifier from the real hex, then the hex.
    public static func colourPhrase(_ name: ColorName, hex: String?, withHex: Bool = true) -> String {
        guard name != .multicolor else { return "multicoloured" }
        var base = name.displayName.lowercased()
        var hexText = ""
        if let h = hex?.replacingOccurrences(of: "#", with: "").uppercased(), h.count == 6, let v = UInt32(h, radix: 16) {
            let r = Double((v >> 16) & 255), g = Double((v >> 8) & 255), b = Double(v & 255)
            let l = (0.299 * r + 0.587 * g + 0.114 * b) / 255, chroma = (max(r, g, b) - min(r, g, b)) / 255
            switch name {
            case .white: if l < 0.97 || chroma > 0.03 { base = "off-white" }
            case .black: break
            case .lightBlue, .cream, .beige, .silver, .gold:
                if l < 0.3 { base = "dark " + base }
            default:
                if l < 0.22 { base = "deep " + base } else if l < 0.35 { base = "dark " + base }
                else if l > 0.82 { base = "pale " + base } else if l > 0.68 { base = "light " + base }
            }
            hexText = " (#\(h))"
        }
        return withHex ? base + hexText : base
    }

    private static let textureNouns: Set<Fabric> = [.jersey, .knit, .fleece, .denim, .corduroy, .twill, .satin, .suede]
    private static let textureCues = ["ribbed", "waffle", "cable-knit", "brushed", "quilted", "pique", "terry"]

    private static func build(_ tags: ItemTags, _ colours: [ColorName], _ hexes: [String], _ label: LabelData?, _ swatch: Bool, _ level: Int) -> String {
        let tail = level < 1 ? "plain light grey background, soft natural shadow, no person, no mannequin, no hanger, no text."
                 : level < 6 ? "plain light grey background, soft shadow, no person, no text." : "plain light grey background, no person."
        let centre = level < 1 ? "centred, " : ""
        let sentence = !swatch ? "" : level < 4 ? " Match the exact colour and fabric texture of the reference swatch." : " Match the reference swatch colour and texture."
        let sub = tags.subcategory
        let fabric = (tags.fabric ?? label?.fabric).flatMap { $0 == .unknown ? nil : $0 }
        var texture: String? = fabric.map(fabricWord)
        if level < 2, let parts = label?.composition, !parts.isEmpty {
            let comp = parts.map { "\($0.percent)% \($0.fibre)" }.joined(separator: ", ")
            texture = comp + (fabric.map { textureNouns.contains($0) ? " " + fabricWord($0) : "" } ?? "")
        }
        let cue = tags.caption.flatMap { c in textureCues.first { c.lowercased().contains($0) } }
        let look = [colourWords(colours, hexes, pattern: tags.pattern, hex: level < 5), cue, texture, level < 3 ? patternWord(tags.pattern) : nil].compactMap { $0 }
        func phrase(_ rest: String...) -> String { (look + rest).filter { !$0.isEmpty }.joined(separator: " ") }
        func a(_ s: String) -> String { (s.first.map { "aeiou".contains($0) } == true ? "an " : "a ") + s }

        switch sub {
        case .sneakers?, .boots?, .formalShoes?, .loafers?, .sandals?, .slides?, .heels?, .flats?, .juttis?:
            return "Side view of a pair of \(phrase(sub!.displayName.lowercased())), toes pointing left, \(centre)\(tail)\(sentence)"
        case .jeans?, .chinos?, .trousers?, .shorts?, .joggers?, .pyjama?, .salwar?:
            let fit = [Fit.slim, .relaxed, .loose, .boxy].contains(tags.fit ?? .regular) ? tags.fit!.rawValue : ""
            let legs = sub == .shorts ? "short legs straight and parallel" : "legs straight and parallel"
            return "\(open) of a pair of \(phrase(fit, sub!.displayName.lowercased())), laid flat, \(legs), waistband at the top, front view, \(centre)\(tail)\(sentence)"
        case .skirt?, .lehengaSkirt?:
            let n = sub == .lehengaSkirt ? "flared lehenga skirt" : "skirt"
            return "\(open) of \(a(phrase(n))), laid flat and spread out symmetrically, waistband at the top, front view, \(centre)\(tail)\(sentence)"
        case .saree?:
            return "\(open) of \(a(phrase("saree"))), folded neatly into a rectangle with the border and pallu visible, \(centre)\(tail)\(sentence)"
        case .dupatta?:
            return "\(open) of \(a(phrase("dupatta"))), folded neatly into a rectangle with the border visible, \(centre)\(tail)\(sentence)"
        case .dress?:
            return "\(open) of \(a(phrase("dress"))), laid flat and symmetrical, front view, hem at the bottom, \(centre)\(tail)\(sentence)"
        case .belt?, .watch?, .chain?, .glasses?, .bag?, .cap?, .other?:
            return "\(open) of \(a(phrase(sub!.displayName.lowercased()))), \(centre)\(tail)\(sentence)"
        case nil:
            return "\(open) of \(a(phrase("garment"))), laid flat, front view, \(centre)\(tail)\(sentence)"
        default: break   // tops and outerwear below
        }

        let sub2 = sub!
        let shortDefault = sub2 == .tshirt || sub2 == .polo
        let sleeve = tags.sleeve ?? (shortDefault ? .short : .long)
        let sleeveWord = sleeve == .sleeveless ? "sleeveless" : sleeve == .short ? "short-sleeve" : "long-sleeve"
        let sleeveClause = sleeve == .sleeveless ? "armholes open" : sleeve == .short ? "sleeves straight out" : (level < 1 ? "long sleeves straight down beside the body" : "long sleeves straight down")
        var adj = "", collarClause = "", extra = ""
        switch tags.collar {
        case .crew?: adj = "crew-neck"
        case .vNeck?: adj = "v-neck"
        case .buttonDown?: collarClause = " with a button-down collar"
        case .mandarin?: collarClause = " with a mandarin collar"
        case .spread?: collarClause = " with a spread collar"
        case .camp?: collarClause = " with a camp collar"
        default: break
        }
        if sub2 == .shirt { extra = ", front button placket" }
        let noun: String
        switch sub2 {
        case .tshirt: noun = "t-shirt"
        case .polo: noun = "polo shirt"; collarClause = ""
        case .hoodie: noun = "hoodie"; adj = ""; collarClause = ""; extra = ", hood laid flat behind the collar, front closed"
        case .jacket, .blazer: noun = sub2.rawValue; adj = ""; extra = ", front closed"
        default: noun = sub2.displayName.lowercased()
        }
        return "\(open) of \(a(phrase(sleeveWord, adj, noun)))\(collarClause), laid flat and symmetrical, \(sleeveClause)\(extra), \(centre)\(tail)\(sentence)"
    }

    static let open = "Front view e-commerce product photo"

    private static func colourWords(_ c: [ColorName], _ hexes: [String], pattern: Pattern?, hex: Bool) -> String? {
        guard let first = c.first else { return nil }
        let main = colourPhrase(first, hex: hexes.first, withHex: hex)
        let patterned = pattern != nil && pattern != .solid && pattern != .other
        if patterned, c.count > 1, c[1] != .multicolor, c[1] != first { return "\(main) and \(c[1].displayName.lowercased())" }
        return main
    }
    /// The proven template (Austin's device test, 14 Nov): one medium sentence starting "Create a…". Image Playground accepted it
    /// where the 300-character, many-clause version was refused. Same wording for every item; only colour, fabric and garment change.
    public static func sentence(for tags: ItemTags, colours: [ColorName], hexes: [String]) -> String {
        let colour = colours.first.map { colourPhrase($0, hex: hexes.first) } ?? ""
        let fabric = tags.fabric.flatMap { $0 == .unknown ? nil : fabricWord($0) }
        let noun = tags.subcategory == .tshirt ? "tshirt" : tags.subcategory.map { $0.displayName.lowercased() } ?? tags.category.map { $0.displayName.lowercased() } ?? "garment"   // Austin's wording: "tshirt"
        let isShirt = tags.subcategory == .shirt
        let sleeve: String? = hasSleeves(tags) ? tags.sleeve.map(sleeveWord) : nil   // never omitted: Image Playground defaults to long sleeves
        let collar: String? = isShirt ? [.buttonDown: "button-down", .mandarin: "mandarin-collar", .camp: "camp-collar"][tags.collar ?? .none] : nil
        let end = "plain light grey background, soft shadow, no person, no text."
        if tags.category == .footwear {
            return "Create a side view e-commerce product photo of a pair of " + [colour, noun].filter { !$0.isEmpty }.joined(separator: " ") + ", " + end
        }
        let layout = tags.category == .bottom ? "laid flat with legs straight" : "laid flat and symmetrical"
        let garment = [colour, fabric, sleeve, collar, noun].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ")
        return "Create a Front view e-commerce product photo of a \(garment), \(layout), \(end)"
    }

    /// Tops, outerwear and dresses have sleeves; the sleeve tag must be known before a sentence is built.
    public static func hasSleeves(_ tags: ItemTags) -> Bool {
        tags.category == .top || tags.category == .outerwear || tags.subcategory == .dress
    }
    public static func needsSleeve(_ tags: ItemTags) -> Bool { hasSleeves(tags) && tags.sleeve == nil }
    static func sleeveWord(_ s: Sleeve) -> String {
        switch s { case .sleeveless: "sleeveless"; case .short: "short-sleeve"; case .threeQuarter: "three-quarter-sleeve"; case .long: "long-sleeve" }
    }

    /// Developer flow (Settings > Developer > Templates): the same sentence style with a neutral mid-grey plain garment, no source image.
    public static func templateSentence(for shape: TemplateShape) -> String {
        let end = "plain light grey background, soft shadow, no person, no text."
        let what: String, layout: String
        switch shape {
        case .tshirtShort: (what, layout) = ("short-sleeve tshirt", "laid flat and symmetrical")
        case .tshirtLong: (what, layout) = ("long-sleeve tshirt", "laid flat and symmetrical")
        case .shirt: (what, layout) = ("button-down long-sleeve shirt", "laid flat and symmetrical")
        case .hoodie: (what, layout) = ("hoodie", "laid flat and symmetrical")
        case .jacket: (what, layout) = ("zip-up jacket", "laid flat and symmetrical")
        case .trousers: (what, layout) = ("pair of trousers", "laid flat with legs straight")
        case .shorts: (what, layout) = ("pair of shorts", "laid flat and symmetrical")
        case .shoes: return "Create a side view e-commerce product photo of a pair of mid-grey plain sneakers, \(end)"
        }
        return "Create a Front view e-commerce product photo of a mid-grey plain \(what), \(layout), \(end)"
    }

    /// Image Playground refuses long sentences (device test, 14 Nov), so the default is 2-3 short positive phrases:
    /// the garment ("black cotton t-shirt"), the shot ("flat lay product photo"), the background. No negatives, hex or people words.
    public static func shortConcepts(for tags: ItemTags, colours: [ColorName]) -> [String] {
        let colour = colours.first.map { $0 == .multicolor ? "multicoloured" : $0.displayName.lowercased() }
        let fabric = tags.fabric.flatMap { $0 == .unknown ? nil : fabricWord($0) }
        let noun = tags.subcategory.map { $0.displayName.lowercased() } ?? tags.category.map { $0.displayName.lowercased() } ?? "garment"
        let collar: String? = tags.subcategory == .shirt ? [.buttonDown: "button-down", .mandarin: "mandarin-collar"][tags.collar ?? .none] : nil
        if tags.category == .footwear {
            return [(["pair of", colour, noun].compactMap { $0 }).joined(separator: " "), "side view product photo", "light grey background"]
        }
        let garment = [colour, collar ?? fabric, noun].compactMap { $0 }.joined(separator: " ")
        return [garment, "flat lay product photo", "light grey background"]
    }

    private static func fabricWord(_ f: Fabric) -> String { f == .cottonLinen ? "cotton-linen" : f.displayName.lowercased() }
    private static func patternWord(_ p: Pattern?) -> String? {
        switch p {
        case .stripe?: "striped"
        case .check?: "checked"
        case .graphic?: "graphic-print"
        case .floral?: "floral"
        case .embroidered?: "embroidered"
        case .textured?: "textured"
        case .colourBlock?: "colour-block"
        default: nil
        }
    }
}

/// What was sent to Image Playground for an item, kept on the item so a regeneration reuses the same object.
public struct ProductDescriptor: Codable, Equatable, Sendable {
    public var prompt: String
    public var swatchFile: String?
    public var hexes: [String]
    public init(prompt: String, swatchFile: String?, hexes: [String]) { self.prompt = prompt; self.swatchFile = swatchFile; self.hexes = hexes }
    /// "prompt | swatch fabric.jpg | #1F2A44": one line for the AI log.
    public var summary: String { [prompt, swatchFile.map { "swatch \($0)" } ?? "no swatch", hexes.map { "#" + $0 }.joined(separator: " ")].joined(separator: " | ") }
}
