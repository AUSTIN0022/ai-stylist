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
                            .frame(width: r.width, height: r.height)
                            .overlay { if selected == slot { RoundedRectangle(cornerRadius: 6).stroke(.tint, lineWidth: 2) } }
                            .overlay(alignment: .bottom) {
                                if !compact, let n = items[slots[slot] ?? UUID()]?.name {
                                    Text(n).font(.system(size: 9, weight: .medium)).lineLimit(1).padding(.horizontal, 6).padding(.vertical, 2)
                                        .background(.white.opacity(0.85), in: Capsule()).padding(2).allowsHitTesting(false)
                                }
                            }
                            .contentShape(Rectangle())
                            .onTapGesture { onSelect?(slot) }
                            .position(x: r.midX, y: r.midY)
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
    }

    /// Cut-out first, the display image when there is none (or it failed).
    private func load() async {
        var out: [Slot: CGImage] = [:]
        for (slot, id) in slots {
            guard let item = items[id] else { continue }
            let urls = [item.cutoutFile.map { store.url(for: $0, id: id) }, store.url(for: item.displayFile, id: id)].compactMap { $0 }
            out[slot] = await Task.detached { urls.lazy.compactMap { ImageCodec.thumbnail(at: $0, maxPixel: 400) }.first }.value
        }
        images = out
    }
}
