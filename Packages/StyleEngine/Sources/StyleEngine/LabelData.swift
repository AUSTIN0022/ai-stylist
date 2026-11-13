import Foundation

public struct FibrePart: Codable, Equatable, Sendable {
    public var percent: Int
    public var fibre: String      // lowercase, e.g. "organic cotton"
    public init(percent: Int, fibre: String) { self.percent = percent; self.fibre = fibre }
}

/// What a neck label, care label or price tag says. Every field is optional; the user edits them as chips.
public struct LabelData: Codable, Equatable, Sendable {
    public var brand: String?
    /// The matched sub-label when the brand belongs to a retailer (brand "Westside", subBrand "WES"). Optional so old JSON decodes.
    public var subBrand: String?
    public var composition: [FibrePart]?
    public var fabric: Fabric?
    public var fit: Fit?
    public var size: String?
    public var mrp: Double?
    // Price-tag fields (round 2). Optional, so JSON saved before they existed still decodes.
    public var salePrice: Double?
    public var colour: String?
    public var styleCode: String?
    /// Verbatim, for duplicate detection only. Never looked up (20-29 codes are store-internal).
    public var barcode: String?
    /// Every line the scanner read, newline-joined (round 3). For debugging the parser and E-LABEL; optional so old JSON decodes.
    public var rawText: String?
    public init() {}
}

public extension ItemTags {
    /// aiRaw < labelData < userOverrides. The label contributes fabric and fit.
    static func effective(aiRaw: ItemTags, label: LabelData?, userOverrides: ItemTags) -> ItemTags {
        var l = ItemTags(); l.fabric = label?.fabric; l.fit = label?.fit
        return aiRaw.overlaid(with: l).overlaid(with: userOverrides)
    }
}

public enum LabelParser {
    /// Built-in brand names, for suggestions.
    public static var brandNames: [String] { BrandCatalog.shared.entries.map(\.name) }

    /// Live-scanner lines plus the still photo's lines: each line once (ignoring case and spacing), first-seen order.
    public static func mergeLines(live: [String], still: [String]) -> [String] {
        var seen = Set<String>()
        return (live + still).filter { seen.insert(squash($0)).inserted }
    }

    /// Same, for several still-photo passes (original, stretched, inverted, zoomed).
    public static func mergeLines(live: [String], passes: [[String]]) -> [String] { mergeLines(live: live, still: passes.flatMap { $0 }) }

    private static let fibreWords: Set<String> = ["cotton", "organic", "polyester", "viscose", "rayon", "nylon", "elastane", "spandex",
        "lycra", "linen", "wool", "silk", "acrylic", "modal", "lyocell", "tencel", "polyamide", "cashmere", "leather", "bamboo",
        "hemp", "flax", "pima", "supima", "combed", "recycled"]
    private static let syntheticFibres = ["polyester", "viscose", "rayon", "nylon", "elastane", "spandex", "lycra", "acrylic", "polyamide", "modal", "lyocell", "tencel"]

    private static func matches(_ pattern: String, _ text: String) -> [NSTextCheckingResult] {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return [] }
        return re.matches(in: text, range: NSRange(text.startIndex..., in: text))
    }
    private static func group(_ m: NSTextCheckingResult, _ i: Int, in text: String) -> String? {
        Range(m.range(at: i), in: text).map { String(text[$0]) }
    }

    public static func parse(text raw: String, barcode: String?, pastBrands: [String] = []) -> LabelData {
        var out = LabelData()
        out.barcode = barcode.flatMap { $0.isEmpty ? nil : $0 }
        let text = raw.lowercased().replacingOccurrences(of: "’", with: "'")
        let lines = text.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard !lines.isEmpty else { return out }
        out.rawText = raw.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.joined(separator: "\n")

        // Brand: the user's past brands first, then the built-in list; a near miss (OCR noise) counts.
        if let (b, sub) = brand(lines: lines, past: pastBrands) { out.brand = b; out.subBrand = sub }

        // Composition: "<n>%" followed by fibre words on the same line.
        var parts: [FibrePart] = []
        for m in matches(#"(\d{1,3})\s*%"#, text) {
            guard let p = group(m, 1, in: text).flatMap(Int.init), let end = Range(m.range, in: text)?.upperBound else { continue }
            let rest = text[end...].prefix { !$0.isNewline && !$0.isNumber }
            var words: [String] = []
            for w in rest.split(whereSeparator: { !$0.isLetter }) {
                if fibreWords.contains(String(w)) { words.append(String(w)) } else { break }
            }
            let part = FibrePart(percent: p, fibre: words.joined(separator: " "))
            if !words.isEmpty, !parts.contains(part) { parts.append(part) }
        }
        if !parts.isEmpty { out.composition = parts }
        out.fabric = fabric(parts: parts, text: text)

        // Fit
        if text.contains("oversized") { out.fit = .loose }
        else if text.contains("boxy") { out.fit = .boxy }
        else if text.contains("relaxed") { out.fit = .relaxed }
        else if !matches(#"slim[\s-]*fit"#, text).isEmpty { out.fit = .slim }
        else if !matches(#"regular[\s-]*fit"#, text).isEmpty { out.fit = .regular }

        out.size = size(lines: lines, text: text, neckLabel: lines.count <= 6 && (out.fit != nil || !parts.isEmpty))

        // Price tag: MRP (labelled one first), sale price, colour, style code. Prices outside 50...200,000 are OCR noise.
        let amount = #"[\s.:\-]*(?:rs|₹|inr)?[\s.:\-]*(\d[\d,]*(?:\.\d+)?)"#
        func sane(_ m: NSTextCheckingResult) -> Double? {
            group(m, 1, in: text).flatMap { Double($0.replacingOccurrences(of: ",", with: "")) }.flatMap { (50...200_000).contains($0) ? $0 : nil }
        }
        let saleMatches = matches(#"(?:sale|offer|our|selling)\s*price"# + amount, text)
        out.salePrice = saleMatches.compactMap(sane).first
        out.mrp = matches(#"(?<![a-z])(?:mrp|m\.r\.p)"# + amount, text).compactMap(sane).first
            ?? matches(#"(?<![a-z])(?:rs|₹|inr)"# + amount, text)
                .filter { m in !saleMatches.contains { NSIntersectionRange($0.range, m.range).length > 0 } }.compactMap(sane).first
        let rawLines = raw.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
        for l in rawLines {
            if out.colour == nil, let m = matches(#"(?i)(?:colou?r|shade)\s*[:\-]\s*(\S.{0,28})$"#, l).first, let c = group(m, 1, in: l) {
                out.colour = c.trimmingCharacters(in: .whitespaces).capitalized
            }
        }
        if let m = matches(#"(?<![a-z])(?:style\s*(?:code|no\.?|number)?|art\.?\s*no\.?|article(?:\s*(?:no\.?|number))?|sku)\s*[:#\-]?\s*((?=[a-z0-9\-/]*\d)[a-z0-9][a-z0-9\-/]{2,})"#, text).first {
            out.styleCode = group(m, 1, in: text)?.uppercased()
        }
        return out
    }


    // MARK: brand and size helpers

    /// Lowercase letters and digits only ("Levi's" -> "levis"), so OCR spacing and punctuation do not matter.
    private static func squash(_ s: String) -> String { String(s.lowercased().filter { $0.isLetter || $0.isNumber }) }

    private static func editDistance(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        var prev = Array(0...b.count)
        for i in 1...max(1, a.count) where !a.isEmpty {
            var cur = [i] + [Int](repeating: 0, count: b.count)
            for j in 1...max(1, b.count) where !b.isEmpty {
                cur[j] = min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1))
            }
            prev = cur
        }
        return prev[b.count]
    }

    /// Whole-word match, or a whole-line near miss (distance 1) for names of 4+ letters (used for the user's past brands).
    private static func lineNames(_ line: String, alias: String) -> Bool {
        if wholeWord(line, alias) { return true }
        let a = squash(alias), l = squash(line)
        return a.count >= 4 && abs(a.count - l.count) <= 1 && editDistance(a, l) <= 1
    }
    private static func wholeWord(_ line: String, _ alias: String) -> Bool {
        !matches("(?<![a-z0-9])" + NSRegularExpression.escapedPattern(for: alias) + "(?![a-z0-9])", line).isEmpty
    }

    private static func result(_ e: BrandEntry) -> (String, String?) {
        guard let p = e.parent, p.lowercased() != e.name.lowercased() else { return (e.name, nil) }
        return (p, e.name)
    }

    private static func brand(lines: [String], past: [String]) -> (String, String?)? {
        for name in past where !squash(name).isEmpty {
            if lines.contains(where: { lineNames($0, alias: name.lowercased()) }) { return (name, nil) }
        }
        let entries = BrandCatalog.shared.entries
        for line in lines {
            let sq = squash(line)
            var best: (len: Int, e: BrandEntry)?
            func offer(_ len: Int, _ e: BrandEntry) { if best == nil || len > best!.len { best = (len, e) } }
            for e in entries {
                for a in e.aliases where wholeWord(line, a) { offer(a.count, e) }
                for a in e.lineOnly where !sq.isEmpty && squash(a) == sq { offer(a.count, e) }
                // ponytail: Westside's logo is 3 letters, so only these OCR look-alikes (WE5, WFS) are accepted, not distance 1.
                if e.name == "WES", !matches(#"^w[e3f][s5]$"#, line).isEmpty { offer(3, e) }
            }
            if let b = best { return result(b.e) }
            // Near miss on the whole line: aliases of 5+ letters, or a parentless brand's own 4-letter name ("Zaro" -> Zara).
            var near: (d: Int, e: BrandEntry)?
            for e in entries {
                for a in e.aliases {
                    let s = squash(a)
                    guard s.count >= 5 || (s.count == 4 && e.parent == nil && s == squash(e.name)) else { continue }
                    guard abs(s.count - sq.count) <= 1 else { continue }
                    let d = editDistance(s, sq)
                    if d <= 1, near == nil || d < near!.d { near = (d, e) }
                }
            }
            if let n = near { return result(n.e) }
        }
        return nil
    }

    /// "Size M", "size: 32", "waist 32"; else "M (38)" / "S/36"; else a lone S/M/L/XL/... line. 2XL -> XXL, 3XL -> XXXL.
    private static func size(lines: [String], text: String, neckLabel: Bool) -> String? {
        let letters = #"(xxxl|3xl|xxl|2xl|xl|xs|s|m|l)"#
        func norm(_ t: String) -> String { ["2xl": "XXL", "3xl": "XXXL"][t] ?? t.uppercased() }
        func inRange(_ t: String) -> Bool { Int(t).map { (26...44).contains($0) || (36...46).contains($0) } ?? true }
        let labelled = matches(#"(?<![a-z])(?:size|waist)\s*[:\-]?\s*(?:"# + letters + #"|(\d{2}))(?![a-z0-9])"#, text)
        for m in labelled {
            if let t = group(m, 1, in: text) { return norm(t) }
            if let t = group(m, 2, in: text), inRange(t) { return t }
        }
        for l in lines {
            if let m = matches("^" + letters + #"\s*[/(]\s*\d{2}\s*\)?$"#, l).first, let t = group(m, 1, in: l) { return norm(t) }
        }
        if let t = lines.first(where: { matches("^" + letters + "$", $0).count == 1 }) { return norm(t) }
        // OCR reads a lone S as "$" or "5" on neck labels. Only there, and never "1"/"l" -> L (too risky).
        return neckLabel && lines.contains { $0 == "$" || $0 == "5" } ? "S" : nil
    }

    private static func fabric(parts: [FibrePart], text: String) -> Fabric? {
        func map(_ fibre: String) -> Fabric? {
            if fibre.contains("cotton") { return .cotton }
            if fibre.contains("linen") || fibre.contains("flax") { return .linen }
            if fibre.contains("wool") || fibre.contains("cashmere") { return .wool }
            if fibre.contains("silk") { return .silk }
            if fibre.contains("leather") { return .leather }
            if syntheticFibres.contains(where: fibre.contains) { return .synthetic }
            return nil
        }
        let top = parts.sorted { $0.percent > $1.percent }
        if top.count >= 2, Set(top.prefix(2).compactMap { map($0.fibre) }) == [.cotton, .linen] { return .cottonLinen }
        if let f = top.first.flatMap({ map($0.fibre) }) { return f }
        let hasCotton = !matches(#"\bcotton\b"#, text).isEmpty, hasLinen = !matches(#"\blinen\b"#, text).isEmpty
        if hasCotton && hasLinen { return .cottonLinen }
        if hasCotton { return .cotton }
        if hasLinen { return .linen }
        return nil
    }
}

/// Pick lists for the label editor.
public enum LabelOptions {
    /// Letters, then "Free size", then waist 26...44. The editor adds "Other..." after these.
    public static let sizes: [String] = ["XS", "S", "M", "L", "XL", "XXL", "XXXL", "Free size"] + (26...44).map(String.init)

    /// Past brands first, then catalog names: sub-brands as "WES · Westside", parents and parentless brands as plain names.
    /// Order: past, names starting with the input, then names or parents with a word starting with it. Empty input gives past brands only.
    public static func brandSuggestions(for input: String, past: [String]) -> [String] {
        let q = input.trimmingCharacters(in: .whitespaces).lowercased()
        if q.isEmpty { return past }
        func words(_ n: String) -> [Substring] { n.lowercased().split(separator: " ") }
        var cands: [(display: String, name: String, parent: String?)] = []
        for e in BrandCatalog.shared.entries {
            if let p = e.parent, p.lowercased() != e.name.lowercased() { cands.append(("\(e.name) · \(p)", e.name, p)) }
            else { cands.append((e.name, e.name, nil)) }
        }
        for p in Set(BrandCatalog.shared.entries.compactMap(\.parent)).sorted() { cands.append((p, p, nil)) }
        let hits = cands.filter { c in words(c.name).contains { $0.hasPrefix(q) } || (c.parent.map { words($0).contains { $0.hasPrefix(q) } } ?? false) }
        let exact = hits.filter { $0.name.lowercased().hasPrefix(q) }, rest = hits.filter { !$0.name.lowercased().hasPrefix(q) }
        var seen = Set<String>()
        let pastHits = past.filter { words($0).contains { $0.hasPrefix(q) } }
        return (pastHits + (exact + rest).map(\.display)).filter { seen.insert($0.lowercased()).inserted }
    }

    /// "WES · Westside" -> ("Westside", "WES"); "Zara" -> ("Zara", nil).
    public static func split(_ suggestion: String) -> (brand: String, subBrand: String?) {
        let p = suggestion.components(separatedBy: " · ")
        return p.count == 2 ? (p[1], p[0]) : (suggestion, nil)
    }
}
