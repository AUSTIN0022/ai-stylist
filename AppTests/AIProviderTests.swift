import CoreGraphics
import Foundation
import StyleEngine
import SwiftData
import Testing
import WardrobeImaging
@testable import AIStylist

// The AI provider seam: one environment, built from a provider, feeds every live factory. Fakes only.

@MainActor private func env(_ provider: FakeAIProvider, store: ImageStore) throws -> (AppEnvironment, ModelContainer) {
    let c = try ModelContainer(for: Schema(Item.allModels), configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    return (AppEnvironment(container: c, provider: provider, store: store), c)
}
private func tempStore() -> ImageStore { ImageStore(root: FileManager.default.temporaryDirectory.appendingPathComponent("prov-\(UUID().uuidString)")) }

@MainActor @Test func provider_stylistLiveUsesTheProvidersParserAndWriter() async throws {
    let parser = FakeIntentParser()
    let (e, c) = try env(FakeAIProvider(parser: parser), store: tempStore())
    let vm = StylistViewModel.live(e, context: c.mainContext)
    await vm.send("diwali dinner")
    await vm.notesTask?.value
    #expect(parser.calls == 1 && vm.store.root == e.store.root)
}

@MainActor @Test func provider_reviewLiveTagsWithTheProvidersTaggerAndLogsIt() async throws {
    let tagger = FakeTagger()
    let store = tempStore()
    let (e, c) = try env(FakeAIProvider(tagger: tagger), store: store)
    let item = Item(originalFile: ImageStore.originalName, cutoutFile: ImageStore.cutoutName, displayFile: ImageStore.displayName)
    let ctx = CGContext(data: nil, width: 40, height: 40, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setFillColor(red: 0.2, green: 0.3, blue: 0.5, alpha: 1); ctx.fill(CGRect(x: 0, y: 0, width: 40, height: 40))
    try store.save(ImageCodec.pngData(ctx.makeImage()!)!, named: ImageStore.cutoutName, for: item.id)
    c.mainContext.insert(item)
    let m = ReviewModel.live(e)
    m.logContext = c.mainContext
    m.beginExisting([item])
    await m.idle()
    #expect(tagger.identityCalls == 1 && m.photos[0].tagState == .done)
    let rows = try c.mainContext.fetch(FetchDescriptor<AIRequestLog>())
    #expect(rows.count == 3 && rows.allSatisfy { $0.provider == "onDevice" && $0.model == "fake-1" })   // fakes don't report a provider: default name
}

@MainActor @Test func provider_unavailableReasonDrivesStatus() {
    let off = FakeAIProvider(unavailableReason: "Apple Intelligence is turned off in Settings.")
    #expect(AIStatus.current(off).manualMode && AIStatus.current(FakeAIProvider()).banner == nil)
}
