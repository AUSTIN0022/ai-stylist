import StyleEngine
import SwiftUI
import WardrobeImaging


/// A fixed-ratio card: each item's cut-out placed by `CardLayout`, fitted inside its slot box, with a small name label
/// inside the cut-out's bottom edge. The note goes below.
struct OutfitCardView: View {
    let slots: [Slot: UUID]
    let items: [UUID: Item]
    let store: ImageStore
    var note: String?
    var selected: Slot?
    var compact = false                    // grid cell: image only, no labels
    var onSelect: ((Slot) -> Void)?
    @State private var images: [Slot: CGImage] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            GeometryReader { geo in
                let rects = CardLayout.layout(images.mapValues { CGSize(width: $0.width, height: $0.height) }, canvas: geo.size)
                ZStack(alignment: .topLeading) {
                    ForEach(rects.keys.sorted(), id: \.self) { slot in
                        let r = rects[slot]!
                        Image(decorative: images[slot]!, scale: 1).resizable()
                            .shadow(color: .black.opacity(0.18), radius: 2, y: 1)
                            .frame(width: r.width, height: r.height)
                            .overlay { if selected == slot { RoundedRectangle(cornerRadius: 6).stroke(.tint, lineWidth: 2) } }
                            .modifier(SlotTap(slot: slot, onSelect: onSelect))
                            .position(x: r.midX, y: r.midY)
                    }
                    // Names on their own top layer: never covered by a neighbouring item, never cut to the item's width.
                    if !compact {
                        ForEach(rects.keys.sorted(), id: \.self) { slot in
                            if let n = items[slots[slot] ?? UUID()]?.name {
                                let r = rects[slot]!
                                Text(n).font(.system(size: 10, weight: .semibold)).foregroundStyle(.black).lineLimit(1).fixedSize()
                                    .padding(.horizontal, 7).padding(.vertical, 2)
                                    .background(.white.opacity(0.92), in: Capsule())
                                    .position(x: min(max(r.midX, 64), geo.size.width - 64), y: min(r.maxY - 10, geo.size.height - 10))
                                    .allowsHitTesting(false)
                            }
                        }
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height)
            }
            .aspectRatio(0.9, contentMode: .fit)
            .background(Color.catalogueGrey)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(.quaternary))
            if !compact {
                if let note { Text(note).font(.footnote).foregroundStyle(.secondary).lineLimit(2) }
            }
        }
        .task(id: slots.map { "\($0.key.rawValue)\($0.value)" }.sorted().joined()) { await load() }
        .onReceive(NotificationCenter.default.publisher(for: .itemImagesChanged)) { _ in Task { await load() } }
    }

    private func load() async {
        var out: [Slot: CGImage] = [:]
        for (slot, id) in slots {
            guard let item = items[id] else { continue }
            if let sticker = await StickerMaker.image(for: id, store: store, cutout: VisionCutoutService(), maxPixel: 600) { out[slot] = sticker; continue }
            let urls = [store.url(for: ImageStore.productName, id: id), item.cutoutFile.map { store.url(for: $0, id: id) }, store.url(for: item.displayFile, id: id)].compactMap { $0 }
            out[slot] = await Task.detached { urls.lazy.filter { FileManager.default.fileExists(atPath: $0.path) }.compactMap { ImageCodec.cachedThumbnail(at: $0, maxPixel: 400) }.first }.value
        }
        images = out
    }
}

/// Slot images take taps only when the card has a listener (swap selection). Without one they must not swallow the tap meant for
/// the card itself (a saved-outfit grid cell is a NavigationLink).
private struct SlotTap: ViewModifier {
    let slot: Slot
    let onSelect: ((Slot) -> Void)?
    func body(content: Content) -> some View {
        if let onSelect { content.contentShape(Rectangle()).onTapGesture { onSelect(slot) } } else { content.allowsHitTesting(false) }
    }
}
