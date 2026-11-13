import Foundation

public struct BrandEntry: Equatable, Sendable {
    public var name: String
    public var parent: String?
    public var owner: String
    public var source: String
    /// Whole-word aliases, lowercase.
    public var aliases: [String]
    /// Only when the whole OCR line equals it (short or common words).
    public var lineOnly: [String]
}

/// Brand list from Resources/brands.json, loaded once.
public struct BrandCatalog: Sendable {
    public let entries: [BrandEntry]
    public static let shared = BrandCatalog.load()

    private struct File: Decodable { var groups: [Group] }
    private struct Group: Decodable { var owner: String; var parent: String?; var source: String; var brands: [Brand] }
    private enum Brand: Decodable {
        case plain(String)
        case full(name: String, aliases: [String], lineOnly: [String])
        private enum K: String, CodingKey { case name, aliases, lineOnly }
        init(from d: Decoder) throws {
            if let s = try? d.singleValueContainer().decode(String.self) { self = .plain(s); return }
            let c = try d.container(keyedBy: K.self)
            self = .full(name: try c.decode(String.self, forKey: .name),
                         aliases: try c.decodeIfPresent([String].self, forKey: .aliases) ?? [],
                         lineOnly: try c.decodeIfPresent([String].self, forKey: .lineOnly) ?? [])
        }
    }

    private static func load() -> BrandCatalog {
        guard let url = Bundle.module.url(forResource: "brands", withExtension: "json"),
              let data = try? Data(contentsOf: url), let file = try? JSONDecoder().decode(File.self, from: data) else { return BrandCatalog(entries: []) }
        var out: [BrandEntry] = []
        for g in file.groups {
            for b in g.brands {
                switch b {
                case .plain(let n): out.append(BrandEntry(name: n, parent: g.parent, owner: g.owner, source: g.source, aliases: [n.lowercased()], lineOnly: []))
                case .full(let n, let a, let l): out.append(BrandEntry(name: n, parent: g.parent, owner: g.owner, source: g.source, aliases: a.map { $0.lowercased() }, lineOnly: l))
                }
            }
        }
        return BrandCatalog(entries: out)
    }
}
