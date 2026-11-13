import Foundation

/// A tag value: one string, or a list of strings. Independent of any taxonomy.
public enum FieldValue: Sendable, Equatable, Codable, ExpressibleByStringLiteral, ExpressibleByArrayLiteral, CustomStringConvertible {
    case single(String)
    case list([String])

    public init(stringLiteral value: String) { self = .single(value) }
    public init(arrayLiteral elements: String...) { self = .list(elements) }

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let s = try? c.decode(String.self) { self = .single(s) }
        else { self = .list(try c.decode([String].self)) }
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self { case .single(let s): try c.encode(s); case .list(let l): try c.encode(l) }
    }

    public var values: [String] {
        switch self { case .single(let s): [s]; case .list(let l): l }
    }
    public var description: String { values.joined(separator: ",") }
}

public typealias EvalTags = [String: FieldValue]

public enum EvalScorer {
    public struct Item: Sendable {
        public var id: String, expected: EvalTags, got: EvalTags
        public init(id: String, expected: EvalTags, got: EvalTags) { self.id = id; self.expected = expected; self.got = got }
    }
    public struct FieldScore: Sendable, Equatable {
        public var right: Int, scored: Int
        public init(right: Int, scored: Int) { self.right = right; self.scored = scored }
    }
    public struct Wrong: Sendable, Equatable {
        public var id: String, field: String, expected: FieldValue, got: FieldValue?
    }
    public struct Report: Sendable {
        public var fields: [String: FieldScore] = [:]
        public var wrong: [Wrong] = []

        /// Percent 0...100, nil when nothing was scored (n/a).
        public func accuracy(_ field: String) -> Double? {
            guard let s = fields[field], s.scored > 0 else { return nil }
            return Double(s.right) / Double(s.scored) * 100
        }
        public func accuracyText(_ field: String) -> String {
            accuracy(field).map { String(format: "%.1f%%", $0) } ?? "n/a"
        }
        public var accuracies: [String: Double?] {
            Dictionary(uniqueKeysWithValues: fields.keys.map { ($0, accuracy($0)) })
        }
    }

    /// Single value: right if equal. List: right if the first expected value is in the answer.
    /// Fields absent from `expected` are not scored; absent from `got` score 0.
    public static func score(_ items: [Item]) -> Report {
        var r = Report()
        for item in items {
            for (field, exp) in item.expected {
                guard let first = exp.values.first else { continue }
                let got = item.got[field]
                let ok = got?.values.contains(first) ?? false
                var s = r.fields[field] ?? .init(right: 0, scored: 0)
                s.scored += 1
                if ok { s.right += 1 } else { r.wrong.append(.init(id: item.id, field: field, expected: exp, got: got)) }
                r.fields[field] = s
            }
        }
        return r
    }
}

public struct TimingSummary: Sendable, Equatable {
    public var median: Double, worst: Double
    public init?(_ seconds: [Double]) {
        guard !seconds.isEmpty else { return nil }
        let s = seconds.sorted(), n = s.count
        median = n % 2 == 1 ? s[n / 2] : (s[n / 2 - 1] + s[n / 2]) / 2
        worst = s[n - 1]
    }
}

/// Pass marks from TEST_PLAN.md section 5 (E-TAG).
public enum PassMarks {
    public static let eTag: [String: Double] = [
        "category": 95, "subcategory": 85, "collar": 85, "sleeve": 85, "pattern": 85,
        "fit": 75, "fabric": 75, "dressCodes": 80,
    ]
    public struct Result: Sendable, Equatable { public var passed: [String], failed: [String], notScored: [String] }

    /// Fields without a mark are ignored. nil accuracy means not scored.
    public static func check(_ accuracies: [String: Double?], marks: [String: Double] = eTag) -> Result {
        var r = Result(passed: [], failed: [], notScored: [])
        for field in marks.keys.sorted() {
            guard let entry = accuracies[field] else { continue }
            guard let acc = entry else { r.notScored.append(field); continue }
            if acc >= marks[field]! { r.passed.append(field) } else { r.failed.append(field) }
        }
        return r
    }
}

public struct IDMatch: Sendable, Equatable {
    public let photosWithoutExpected: [String], expectedWithoutPhoto: [String]
    public var isComplete: Bool { photosWithoutExpected.isEmpty && expectedWithoutPhoto.isEmpty }
    public init(photoIDs: [String], expectedIDs: [String]) {
        photosWithoutExpected = Set(photoIDs).subtracting(expectedIDs).sorted()
        expectedWithoutPhoto = Set(expectedIDs).subtracting(photoIDs).sorted()
    }
}

public enum ExpectedFile {
    public enum DecodeError: Error, Equatable, CustomStringConvertible {
        case notJSON(String)
        case badShape(id: String, field: String?)
        case unknownField(id: String, field: String)
        case invalidValue(id: String, field: String, value: String)

        public var description: String {
            switch self {
            case .notJSON(let m): "expected.json is not valid JSON: \(m)"
            case .badShape(let id, let f): "item '\(id)'" + (f.map { ", field '\($0)'" } ?? "") + ": expected a string or list of strings"
            case .unknownField(let id, let f): "item '\(id)': unknown field '\(f)'"
            case .invalidValue(let id, let f, let v): "item '\(id)', field '\(f)': '\(v)' is not an allowed value"
            }
        }
    }

    /// Decodes `{ id: { field: "x" | ["x", ...] } }` and checks each value against `allowed[field]`.
    public static func decode(_ data: Data, allowed: [String: Set<String>]) throws -> [String: EvalTags] {
        let root: Any
        do { root = try JSONSerialization.jsonObject(with: data) } catch { throw DecodeError.notJSON("\(error.localizedDescription)") }
        guard let items = root as? [String: Any] else { throw DecodeError.notJSON("top level must be an object keyed by item id") }
        var out: [String: EvalTags] = [:]
        for id in items.keys.sorted() {
            guard let fields = items[id] as? [String: Any] else { throw DecodeError.badShape(id: id, field: nil) }
            var tags: EvalTags = [:]
            for field in fields.keys.sorted() {
                guard let ok = allowed[field] else { throw DecodeError.unknownField(id: id, field: field) }
                let value: FieldValue
                switch fields[field] {
                case let s as String: value = .single(s)
                case let l as [String]: value = .list(l)
                default: throw DecodeError.badShape(id: id, field: field)
                }
                for v in value.values where !ok.contains(v) { throw DecodeError.invalidValue(id: id, field: field, value: v) }
                tags[field] = value
            }
            out[id] = tags
        }
        return out
    }
}
