import Foundation

// Image storage decision (Sprint 1): on-device only, under Application Support/items/<item id>/
// with three files: original.jpg, cutout.png, display.jpg. The database stores file names only,
// never image bytes or absolute paths (those change between installs). S3/R2 comes later with a
// backend; this struct is the one place to change when it does.

public struct ImageStore: Sendable {
    public static let originalName = "original.jpg"
    public static let cutoutName = "cutout.png"
    public static let displayName = "display.jpg"
    public static let labelName = "label.jpg"

    public let root: URL
    public init(root: URL) { self.root = root }

    /// Application Support/items
    public static var standard: ImageStore {
        let base = (try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true))
            ?? FileManager.default.temporaryDirectory
        return ImageStore(root: base.appendingPathComponent("items", isDirectory: true))
    }

    public func folder(for id: UUID) -> URL { root.appendingPathComponent(id.uuidString, isDirectory: true) }
    public func url(for name: String, id: UUID) -> URL { folder(for: id).appendingPathComponent(name) }

    public func save(_ data: Data, named name: String, for id: UUID) throws {
        try FileManager.default.createDirectory(at: folder(for: id), withIntermediateDirectories: true)
        try data.write(to: url(for: name, id: id), options: .atomic)
    }

    public func load(_ name: String, for id: UUID) throws -> Data { try Data(contentsOf: url(for: name, id: id)) }

    public func deleteItem(_ id: UUID) { try? FileManager.default.removeItem(at: folder(for: id)) }

    /// Deletes item folders whose id is not in `keeping` (left behind by a force-quit during review).
    /// Only folders named like a UUID are touched. Returns how many were removed.
    @discardableResult
    public func removeOrphans(keeping: Set<UUID>) -> Int {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? []
        let orphans = names.compactMap(UUID.init(uuidString:)).filter { !keeping.contains($0) }
        orphans.forEach(deleteItem)
        return orphans.count
    }
}
