import Foundation
import Testing
@testable import WardrobeImaging

/// S1B-M10 follow-up: a force-quit during review leaves image folders with no database row.
@Test func removeOrphansKeepsOnlyKnownItems() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let store = ImageStore(root: root)
    let kept = UUID(), orphan = UUID()
    try store.save(Data([1]), named: ImageStore.originalName, for: kept)
    try store.save(Data([2]), named: ImageStore.originalName, for: orphan)

    let removed = store.removeOrphans(keeping: [kept])

    #expect(removed == 1)
    #expect(FileManager.default.fileExists(atPath: store.folder(for: kept).path))
    #expect(!FileManager.default.fileExists(atPath: store.folder(for: orphan).path))
}

@Test func removeOrphansIgnoresMissingRootAndStrayFiles() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    #expect(ImageStore(root: root).removeOrphans(keeping: []) == 0)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try Data().write(to: root.appendingPathComponent("notes.txt"))
    #expect(ImageStore(root: root).removeOrphans(keeping: []) == 0)
}
