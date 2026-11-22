import StyleEngine
import SwiftData
import SwiftUI
import WardrobeImaging

/// Sprint 5 builder: canvas on top, item drawer below. Every gesture ends in an `OutfitCanvas` call (tested as plain data).
/// Drag a thumbnail up to place it, or tap it to place it at its slot's default position.
struct OutfitBuilderView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Item.createdAt, order: .reverse) private var items: [Item]
    @State private var canvas: OutfitCanvas
    @State private var selected: UUID?
    @State private var name: String
    @State private var occasion: Occasion?
    @State private var tab: DrawerTab = .tops
    @State private var canvasSize = CGSize(width: 1, height: 1)
    let editing: Outfit?

    init(editing: Outfit? = nil, start: OutfitCanvas = OutfitCanvas()) {
        self.editing = editing
        _canvas = State(initialValue: start)
        _name = State(initialValue: editing?.name ?? "")
        _occasion = State(initialValue: editing?.occasion.flatMap(Occasion.init(rawValue:)))
    }

    enum DrawerTab: String, CaseIterable, Identifiable {
        case tops = "Tops", bottoms = "Bottoms", footwear = "Footwear", outerwear = "Outerwear", accessories = "Accessories", sets = "Sets"
        var id: String { rawValue }
    }

    private var byId: [UUID: Item] { Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a }) }
    private var wardrobe: [EngineItem] { items.map(\.engineItem) }

    private func drawer(_ t: DrawerTab) -> [Item] {
        items.filter { i in
            guard i.status == .ready else { return false }
            switch t {
            case .sets: return i.setGroupId != nil
            default:
                guard i.setGroupId == nil else { return false }
                let c = i.tags.category
                switch t {
                case .tops: return c == .top || c == .onePiece
                case .bottoms: return c == .bottom
                case .footwear: return c == .footwear
                case .outerwear: return c == .outerwear
                case .accessories: return c == .accessory
                case .sets: return false
                }
            }
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                GeometryReader { geo in
                    ZStack {
                        Color.catalogueGrey.onTapGesture { selected = nil }
                        ForEach(canvas.drawOrder, id: \.itemId) { p in
                            if let item = byId[p.itemId] {
                                PlacedItemView(item: item, store: env.store, placed: p, isSelected: selected == p.itemId, canvasSize: geo.size,
                                               onSelect: { selected = p.itemId; canvas.bringToFront(p.itemId) },
                                               onMove: { canvas.move(p.itemId, by: $0, in: geo.size) },
                                               onScale: { canvas.scale(p.itemId, to: $0) },
                                               onRemove: { canvas.remove(p.itemId); selected = nil },
                                               onBack: { canvas.sendToBack(p.itemId) })
                            }
                        }
                    }
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()
                    .onAppear { canvasSize = geo.size }
                    .onChange(of: geo.size) { _, s in canvasSize = s }
                    .dropDestination(for: String.self) { ids, loc in
                        guard let s = ids.first, let id = UUID(uuidString: s), let item = byId[id] else { return false }
                        canvas.add(item.engineItem, using: wardrobe)
                        canvas.place(id, at: loc, in: geo.size)
                        selected = id
                        return true
                    }
                }
                .frame(maxHeight: .infinity).layoutPriority(1)
                .overlay(alignment: .center) {
                    if canvas.items.isEmpty { Text("Tap or drag clothes here").foregroundStyle(.secondary) }
                }
                Divider()
                VStack(spacing: 6) {
                    Picker("Category", selection: $tab) { ForEach(DrawerTab.allCases) { Text($0.rawValue).tag($0) } }
                        .pickerStyle(.menu).accessibilityIdentifier("category-picker").frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 12)
                    let list = drawer(tab)
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(spacing: 8) {
                            ForEach(list) { item in
                                ItemCell(item: item, store: env.store).frame(width: 78)
                                    .draggable(item.id.uuidString)
                                    .onTapGesture { canvas.add(item.engineItem, using: wardrobe); selected = item.id }
                                    .accessibilityElement(children: .ignore).accessibilityLabel(item.name)
                                    .accessibilityIdentifier("drawer-\(item.name)").accessibilityAddTraits(.isButton)
                                    .opacity(canvas.items.contains { $0.itemId == item.id } ? 0.4 : 1)
                            }
                            if list.isEmpty { Text("Nothing in \(tab.rawValue.lowercased()) yet").font(.footnote).foregroundStyle(.secondary).padding() }
                        }.padding(.horizontal, 12)
                    }.frame(height: 110)
                }.padding(.vertical, 8).background(.bar)
            }
            .navigationTitle(editing == nil ? "New outfit" : "Edit outfit").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        OutfitSaver.saveManual(canvas, name: name, occasion: occasion, editing: editing, in: context); dismiss()
                    }.disabled(!OutfitSaver.canSave(canvas))
                }
                ToolbarItem(placement: .bottomBar) {
                    HStack {
                        TextField("Name (optional)", text: $name).textFieldStyle(.roundedBorder)
                        Picker("Occasion", selection: $occasion) {
                            Text("No occasion").tag(Occasion?.none)
                            ForEach(Occasion.allCases, id: \.self) { Text($0.title).tag(Optional($0)) }
                        }.pickerStyle(.menu)
                    }
                }
            }
        }
    }
}

/// One item on the canvas. Drag moves it from where it was (offset applied on top of the stored position); pinch resizes the selected item.
private struct PlacedItemView: View {
    let item: Item, store: ImageStore, placed: PlacedItem, isSelected: Bool, canvasSize: CGSize
    let onSelect: () -> Void, onMove: (CGSize) -> Void, onScale: (Double) -> Void, onRemove: () -> Void, onBack: () -> Void
    @State private var drag: CGSize = .zero
    @State private var pinch: Double = 1

    var body: some View {
        let side = min(canvasSize.width, canvasSize.height) * OutfitCanvas.baseSize * 1.6 * placed.scale * pinch
        StickerImage(item: item, store: store)
            .frame(width: side, height: side)
            .overlay { if isSelected { RoundedRectangle(cornerRadius: 6).stroke(.tint, lineWidth: 2) } }
            .overlay(alignment: .topTrailing) {
                if isSelected {
                    HStack(spacing: 4) {
                        Button(action: onBack) { Image(systemName: "square.3.layers.3d.down.left") }
                        Button(role: .destructive, action: onRemove) { Image(systemName: "xmark.circle.fill") }
                    }.buttonStyle(.borderedProminent).controlSize(.mini).offset(y: -26)
                }
            }
            .position(x: placed.x * canvasSize.width + drag.width, y: placed.y * canvasSize.height + drag.height)
            .gesture(
                DragGesture()
                    .onChanged { drag = $0.translation }
                    .onEnded { v in onMove(v.translation); drag = .zero }
                    .simultaneously(with: MagnifyGesture()
                        .onChanged { if isSelected { pinch = $0.magnification } }
                        .onEnded { m in if isSelected { onScale(placed.scale * m.magnification) }; pinch = 1 })
            )
            .onTapGesture(perform: onSelect)
    }
}

/// A saved outfit drawn from its stored layout (grid cells and the detail screen).
struct CanvasOutfitView: View {
    let canvas: OutfitCanvas
    let items: [UUID: Item]
    let store: ImageStore
    var body: some View {
        GeometryReader { geo in
            ZStack {
                ForEach(canvas.drawOrder, id: \.itemId) { p in
                    if let item = items[p.itemId] {
                        let side = min(geo.size.width, geo.size.height) * OutfitCanvas.baseSize * 1.6 * p.scale
                        StickerImage(item: item, store: store)
                            .frame(width: side, height: side).position(x: p.x * geo.size.width, y: p.y * geo.size.height)
                    }
                }
            }.frame(width: geo.size.width, height: geo.size.height).clipped()
        }
        .aspectRatio(0.9, contentMode: .fit).background(Color.catalogueGrey)
        .clipShape(RoundedRectangle(cornerRadius: 12)).overlay(RoundedRectangle(cornerRadius: 12).stroke(.quaternary))
    }
}
