import Foundation
import SwiftData
import Testing
import WardrobeImaging
@testable import AIStylist

// These need SwiftData app models, so they build with the app target and run on a simulator or iPhone.

@MainActor private func onDiskContainer(_ dir: URL) throws -> ModelContainer {
    try ModelContainer(for: Schema(Item.allModels), configurations: ModelConfiguration(url: dir.appendingPathComponent("test.store")))
}

private func tempDir() -> URL {
    let d = FileManager.default.temporaryDirectory.appendingPathComponent("aistylist-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
    return d
}

@Test func S1_U23_itemStoresFileNamesOnly() throws {
    let root = tempDir(); defer { try? FileManager.default.removeItem(at: root) }
    let item = Item(originalFile: ImageStore.originalName, cutoutFile: ImageStore.cutoutName, displayFile: ImageStore.displayName)
    try ImageStore(root: root).save(Data([1]), named: item.displayFile, for: item.id)
    #expect(!item.displayFile.contains("/"))
    // Resolve against a new root after moving the folder: the names still find the file.
    let moved = tempDir(); defer { try? FileManager.default.removeItem(at: moved) }
    try FileManager.default.removeItem(at: moved)
    try FileManager.default.moveItem(at: root, to: moved)
    #expect(FileManager.default.fileExists(atPath: ImageStore(root: moved).url(for: item.displayFile, id: item.id).path))
}

@MainActor @Test func S1_I05_persistenceAcrossReopen() throws {
    let dir = tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
    let id: UUID
    do {
        let c = try onDiskContainer(dir)
        let item = Item(originalFile: "original.jpg", cutoutFile: "cutout.png", displayFile: "display.jpg")
        item.hexColors = ["B5522B"]; id = item.id
        c.mainContext.insert(item); try c.mainContext.save()
    }
    let again = try onDiskContainer(dir)
    let items = try again.mainContext.fetch(FetchDescriptor<Item>())
    #expect(items.count == 1 && items[0].id == id && items[0].displayFile == "display.jpg" && items[0].hexColors == ["B5522B"])
}

@MainActor @Test func S1_I06_deleteRemovesRowAndFolder() throws {
    let dir = tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
    let store = ImageStore(root: dir.appendingPathComponent("items"))
    let c = try onDiskContainer(dir)
    let item = Item(originalFile: "original.jpg", cutoutFile: nil, displayFile: "display.jpg")
    try store.save(Data([1]), named: "display.jpg", for: item.id)
    c.mainContext.insert(item); try c.mainContext.save()
    Item.delete(item, in: c.mainContext, store: store)
    #expect(try c.mainContext.fetch(FetchDescriptor<Item>()).isEmpty)
    #expect(!FileManager.default.fileExists(atPath: store.folder(for: item.id).path))
}

@MainActor @Test func S1_I07_allSixModels() throws {
    let dir = tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
    let container = try onDiskContainer(dir)   // keep the container alive: the context does not retain it
    let ctx = container.mainContext
    let outfit = Outfit(name: "Office", source: .ai)
    ctx.insert(Item(originalFile: "o", cutoutFile: nil, displayFile: "d"))
    ctx.insert(outfit)
    ctx.insert(OutfitItem(outfitId: outfit.id, itemId: UUID(), slot: "top"))
    ctx.insert(WearLog(outfitId: outfit.id, itemIds: [UUID()], date: .now))
    ctx.insert(AIRequestLog(purpose: "tagA", provider: "onDevice", model: "system", durationSeconds: 1.2, success: true))
    ctx.insert(FeedbackEvent(outfitId: outfit.id, action: "saved"))
    try ctx.save()
    #expect(try ctx.fetchCount(FetchDescriptor<Item>()) == 1)
    #expect(try ctx.fetchCount(FetchDescriptor<Outfit>()) == 1)
    #expect(try ctx.fetchCount(FetchDescriptor<OutfitItem>()) == 1)
    #expect(try ctx.fetchCount(FetchDescriptor<WearLog>()) == 1)
    #expect(try ctx.fetchCount(FetchDescriptor<AIRequestLog>()) == 1)
    #expect(try ctx.fetchCount(FetchDescriptor<FeedbackEvent>()) == 1)
}
