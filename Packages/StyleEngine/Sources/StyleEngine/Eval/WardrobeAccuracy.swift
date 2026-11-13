import Foundation

/// One saved item for the "eval from my wardrobe" screen. `effective` = raw < label < user corrections.
public struct AccuracySample: Sendable {
    public var id: String
    public var aiRaw: ItemTags
    public var effective: ItemTags
    /// The label as the scanner parsed it, and as it is now (after the user's edits). nil = no label.
    public var labelScan: LabelData?
    public var label: LabelData?
    public init(id: String, aiRaw: ItemTags, effective: ItemTags, labelScan: LabelData? = nil, label: LabelData? = nil) {
        self.id = id; self.aiRaw = aiRaw; self.effective = effective; self.labelScan = labelScan; self.label = label
    }
}

/// E-TAG computed from everyday use: the AI's raw answer against what the user ended up with.
/// A field the user changed (or filled in after the AI left it empty) is an AI miss. Pass marks: TEST_PLAN section 5.
public enum WardrobeAccuracy {
    public static let marks: [String: Double] = [
        "category": 95, "subcategory": 85, "collar": 85, "sleeve": 85, "pattern": 85, "fit": 75, "fabric": 75, "dressCodes": 80,
    ]
    /// Fields shown, in table order (the first eight have a pass mark).
    public static let fields = ["category", "subcategory", "collar", "sleeve", "pattern", "fit", "fabric", "dressCodes", "styleOrigin", "length", "seasons", "statement"]

    public struct Report: Sendable {
        public var itemCount = 0
        public var tag = EvalScorer.Report()
        public var result = PassMarks.Result(passed: [], failed: [], notScored: [])
        public var labelItems = 0
        public var labelFields: [String: EvalScorer.FieldScore] = [:]
        public var wrong: [EvalScorer.Wrong] { tag.wrong }
        public func accuracy(_ field: String) -> Double? { tag.accuracy(field) }
        /// Percent of label fields the user left as scanned; nil when no item has a label.
        public var labelAccuracy: Double? {
            let r = labelFields.values.reduce(0) { $0 + $1.right }, n = labelFields.values.reduce(0) { $0 + $1.scored }
            return n == 0 ? nil : Double(r) / Double(n) * 100
        }
    }

    public static func report(_ samples: [AccuracySample]) -> Report {
        var r = Report()
        r.itemCount = samples.count
        r.tag = EvalScorer.score(samples.map { .init(id: $0.id, expected: evalTags($0.effective), got: evalTags($0.aiRaw)) })
        r.result = PassMarks.check(Dictionary(uniqueKeysWithValues: fields.map { ($0, r.tag.accuracy($0)) }), marks: marks)
        for s in samples {
            guard let scan = s.labelScan else { continue }
            r.labelItems += 1
            for (field, a, b) in labelPairs(scan, s.label ?? scan) where a != nil || b != nil {
                var f = r.labelFields[field] ?? .init(right: 0, scored: 0)
                f.scored += 1; if a == b { f.right += 1 }
                r.labelFields[field] = f
            }
        }
        return r
    }

    static func evalTags(_ t: ItemTags) -> EvalTags {
        var o: EvalTags = [:]
        func one(_ k: String, _ v: (any RawRepresentable<String>)?) { if let v { o[k] = .single(v.rawValue) } }
        one("category", t.category); one("subcategory", t.subcategory); one("styleOrigin", t.styleOrigin); one("pattern", t.pattern)
        one("fabric", t.fabric); one("fit", t.fit); one("length", t.length); one("collar", t.collar); one("sleeve", t.sleeve); one("statement", t.statement)
        if let d = t.dressCodes, !d.isEmpty { o["dressCodes"] = .list(d.map(\.rawValue)) }
        if let s = t.seasons, !s.isEmpty { o["seasons"] = .list(s.map(\.rawValue)) }
        return o
    }

    private static func labelPairs(_ a: LabelData, _ b: LabelData) -> [(String, String?, String?)] {
        func comp(_ l: LabelData) -> String? { l.composition.map { $0.map { "\($0.percent) \($0.fibre)" }.joined(separator: ",") } }
        func num(_ d: Double?) -> String? { d.map { String($0) } }
        return [("brand", a.brand, b.brand), ("subBrand", a.subBrand, b.subBrand), ("composition", comp(a), comp(b)),
                ("fabric", a.fabric?.rawValue, b.fabric?.rawValue), ("fit", a.fit?.rawValue, b.fit?.rawValue), ("size", a.size, b.size),
                ("mrp", num(a.mrp), num(b.mrp)), ("salePrice", num(a.salePrice), num(b.salePrice)),
                ("colour", a.colour, b.colour), ("styleCode", a.styleCode, b.styleCode)]
    }

    /// Same table format as EVAL_SPRINT0.md, plus label accuracy and the wrong answers.
    public static func markdown(_ r: Report, date: String) -> String {
        var out = "## E-TAG accuracy from my wardrobe (\(r.itemCount) reviewed items, \(date))\n\n"
        out += "| field | accuracy | pass mark | pass? |\n|---|---|---|---|\n"
        for f in fields {
            let mark = marks[f].map { "\(Int($0))%" } ?? "-"
            let pass = marks[f] == nil ? "-" : r.result.passed.contains(f) ? "pass" : r.result.failed.contains(f) ? "FAIL" : "n/a"
            out += "| \(f) | \(r.tag.accuracyText(f)) | \(mark) | \(pass) |\n"
        }
        out += "\n## Label read accuracy (\(r.labelItems) items with a label)\n\n"
        out += "Overall: \(r.labelAccuracy.map { String(format: "%.1f%%", $0) } ?? "n/a")\n\n| field | right | scanned |\n|---|---|---|\n"
        for f in r.labelFields.keys.sorted() { out += "| \(f) | \(r.labelFields[f]!.right) | \(r.labelFields[f]!.scored) |\n" }
        out += "\n## Wrong answers\n\n| photo id | field | expected | got |\n|---|---|---|---|\n"
        for w in r.wrong { out += "| \(w.id) | \(w.field) | \(w.expected) | \(w.got.map(\.description) ?? "-") |\n" }
        return out
    }
}
