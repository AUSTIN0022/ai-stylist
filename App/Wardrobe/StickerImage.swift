import SwiftUI
import WardrobeImaging

/// An item drawn as a sticker (trimmed, thin white outline, light shadow). Falls back to the plain product photo, cut-out or
/// display image while the sticker is being made or when there is no clear subject. Reloads when the item's images change.
struct StickerImage: View {
    let item: Item
    let store: ImageStore
    @State private var image: CGImage?
    @State private var isSticker = false
    @State private var reloads = 0

    var body: some View {
        Group {
            if let image {
                Image(decorative: image, scale: 1).resizable().scaledToFit()
                    .shadow(color: .black.opacity(isSticker ? 0.18 : 0), radius: 2, y: 1)
            } else { Color.clear }
        }
        .task(id: "\(item.id)#\(reloads)") { await load() }
        .onReceive(NotificationCenter.default.publisher(for: .itemImagesChanged)) { n in
            if (n.object as? UUID).map({ $0 == item.id }) ?? true { reloads += 1 }
        }
    }

    private func load() async {
        let (id, store, cutFile, display) = (item.id, store, item.cutoutFile, item.displayFile)
        if let s = await StickerMaker.image(for: id, store: store, cutout: VisionCutoutService(), maxPixel: 700) { image = s; isSticker = true; return }
        let urls = [store.url(for: ImageStore.productName, id: id), cutFile.map { store.url(for: $0, id: id) }, store.url(for: display, id: id)].compactMap { $0 }
        image = await Task.detached { urls.lazy.filter { FileManager.default.fileExists(atPath: $0.path) }.compactMap { ImageCodec.thumbnail(at: $0, maxPixel: 700) }.first }.value
        isSticker = false
    }
}
