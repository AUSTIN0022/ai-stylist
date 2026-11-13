import CoreGraphics
import Foundation
import Testing
@testable import WardrobeImaging

struct FakeError: Error {}

/// Returns a prepared cut-out; records peak concurrency.
actor FakeCutout: CutoutProviding {
    var fail = false, mask: Mask
    var running = 0, peak = 0, calls = 0
    init(fail: Bool = false, mask: Mask = rectMask(100, 100, x: 18, y: 18, rw: 64, rh: 64)) { self.fail = fail; self.mask = mask }
    func cutout(from image: CGImage, box: CGRect?) async throws -> CutoutResult {
        running += 1; peak = max(peak, running); calls += 1
        try await Task.sleep(for: .milliseconds(2))
        running -= 1
        if fail { throw FakeError() }
        return CutoutResult(cutout: makeImage(80, 100) { fill($0, "B5522B", 0, 0, 80, 100) }, mask: mask)
    }
}

private func source(_ hex: String = "336699") -> Data { jpeg(checkerboardTinted(hex)) }
private func checkerboardTinted(_ hex: String) -> CGImage { makeImage(300, 200) { fill($0, hex, 0, 0, 300, 200) } }

@Test func S1_I03_cutoutFailureStillSavesItem() async throws {
    let root = tempRoot(); defer { try? FileManager.default.removeItem(at: root) }
    let store = ImageStore(root: root)
    let p = ItemImageProcessor(cutout: FakeCutout(fail: true), store: store)
    let r = try await p.process(source())
    #expect(r.cutoutFailed && r.lastError != nil)
    #expect(r.cutoutFile == nil && r.hexColors.isEmpty)
    let display = try #require(ImageCodec.decode(try store.load(r.displayFile, for: r.itemID)))
    #expect(display.width == display.height)                       // centre-cropped square original
    let px = PixelBuffer(display).rgba(display.width / 2, display.height / 2)
    #expect(abs(Int(px.0) - 0x33) < 6 && abs(Int(px.2) - 0x99) < 6)
    #expect(try store.load(r.originalFile, for: r.itemID).count > 0)
}

@Test func successSavesThreeFilesAndColours() async throws {
    let root = tempRoot(); defer { try? FileManager.default.removeItem(at: root) }
    let store = ImageStore(root: root)
    let r = try await ItemImageProcessor(cutout: FakeCutout(), store: store).process(source())
    #expect(!r.cutoutFailed)
    for f in [r.originalFile, r.cutoutFile!, r.displayFile] { #expect(!(try store.load(f, for: r.itemID)).isEmpty) }
    #expect(r.colorNames == [.rust])
}

@MainActor @Test func S1_I04_batchOfTwentyOneAtATimeInOrder() async throws {
    let root = tempRoot(); defer { try? FileManager.default.removeItem(at: root) }
    let fake = FakeCutout()
    let p = ItemImageProcessor(cutout: fake, store: ImageStore(root: root))
    let datas = (0..<20).map { source(String(format: "%02X6699", $0 * 10)) }
    var seen: [Int] = []
    await p.processBatch(count: 20, load: { datas[$0] }) { index, result in
        seen.append(index)
        #expect((try? result.get().lastError) == .some(nil))
    }
    #expect(seen == Array(0..<20))
    #expect(await fake.peak == 1)
    #expect(await fake.calls == 20)
    #expect((try FileManager.default.contentsOfDirectory(atPath: root.path)).count == 20)
}

@Test func S1_I08_flaggedImageStillProducesItem() async throws {
    let root = tempRoot(); defer { try? FileManager.default.removeItem(at: root) }
    let tiny = rectMask(100, 100, x: 45, y: 45, rw: 10, rh: 10)   // 1%
    let r = try await ItemImageProcessor(cutout: FakeCutout(mask: tiny), store: ImageStore(root: root)).process(jpeg(checkerboard()))
    #expect(r.verdict == .noClearItem)
    #expect(!r.cutoutFailed)
    #expect(try ImageStore(root: root).load(r.displayFile, for: r.itemID).count > 0)
}
