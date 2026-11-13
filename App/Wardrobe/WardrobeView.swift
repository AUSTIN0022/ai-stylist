import PhotosUI
import StyleEngine
import SwiftData
import SwiftUI
import WardrobeImaging

struct WardrobeView: View {
    @Query(sort: \Item.createdAt, order: .reverse) private var items: [Item]
    @Environment(\.modelContext) private var context
    @State private var review: ReviewModel?
    @State private var fromCamera: ReviewModel?   // opened once the camera has dismissed
    @State private var picked: [PhotosPickerItem] = []
    @State private var showCamera = false
    @State private var filter = WardrobeFilter()
    @State private var showSettings = false

    private let columns = [GridItem(.adaptive(minimum: 104), spacing: 8)]
    private var store: ImageStore { .standard }

    /// Sections by category, then "Unsorted" for items with no tags yet.
    private var sections: [(title: String, items: [Item])] { Self.sections(for: filtered) }

    private var snapshots: [WardrobeFilter.Snapshot] { items.map(\.snapshot) }
    private var filtered: [Item] {
        guard filter.isActive else { return items }
        let ids = Set(filter.apply(to: snapshots).map(\.id))
        return items.filter { ids.contains($0.id) }
    }

    /// Grouped by effective category (AI < label < user correction).
    static func sections(for items: [Item]) -> [(title: String, items: [Item])] {
        let tagged = items.map { ($0, $0.tags.category) }
        var out: [(String, [Item])] = StyleEngine.Category.allCases.compactMap { c in
            let m = tagged.filter { $0.1 == c }.map(\.0)
            return m.isEmpty ? nil : (c.displayName, m)
        }
        let unsorted = tagged.filter { $0.1 == nil }.map(\.0)
        if !unsorted.isEmpty { out.append(("Unsorted", unsorted)) }
        return out
    }

    /// Items with no category yet (the "Unsorted" section).
    static func unsortedItems(_ items: [Item]) -> [Item] { items.filter { $0.tags.category == nil } }

    private var content: some View {
    LazyVStack(alignment: .leading, spacing: 20) {
        if !items.isEmpty { FilterBar(filter: $filter, snaps: snapshots, shown: filtered.count, total: items.count) }
        ForEach(sections, id: \.title) { section in
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(section.title).font(.headline)
                    Spacer()
                    if section.title == "Unsorted" {
                        Button("Sort these (\(section.items.count))") {
                            let m = ReviewModel.live(); m.beginExisting(Self.unsortedItems(filtered)); review = m
                        }.buttonStyle(.bordered).controlSize(.small)
                    }
                }
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(section.items) { item in
                        NavigationLink(value: item.id) { ItemCell(item: item, store: store) }.buttonStyle(.plain)
                    }
                }
            }
        }
        if !items.isEmpty && filtered.isEmpty {
            ContentUnavailableView("No items match", systemImage: "magnifyingglass",
                                   description: Text("Try removing a filter or changing the search."))
                .padding(.top, 40)
        }
        if items.isEmpty {
            ContentUnavailableView("No clothes yet", systemImage: "tshirt",
                                   description: Text("Add photos from your library or take them with the camera."))
                .padding(.top, 60)
        }
    }
    .padding(16)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                content
            }
            .navigationTitle("Wardrobe")
            .searchable(text: $filter.text, prompt: "Search name, brand, colour")
            .navigationDestination(for: UUID.self) { id in
                if let item = items.first(where: { $0.id == id }) { ItemDetailView(item: item, store: store) }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showSettings = true } label: { Label("Settings", systemImage: "gearshape") }
                }
                ToolbarItemGroup(placement: .primaryAction) {
                    Button { showCamera = true } label: { Label("Camera", systemImage: "camera") }
                    PhotosPicker(selection: $picked, maxSelectionCount: 20, matching: .images) {
                        Label("Photo library", systemImage: "photo.on.rectangle")
                    }
                }
            }
            .onChange(of: picked) { _, new in
                guard !new.isEmpty else { return }
                let chosen = new
                picked = []
                let m = ReviewModel.live()
                m.begin(count: chosen.count) { i in try? await chosen[i].loadTransferable(type: Data.self) }
                review = m
            }
            .fullScreenCover(isPresented: $showCamera, onDismiss: { review = fromCamera; fromCamera = nil }) {
                CameraView { shots in
                    let m = ReviewModel.live()
                    m.begin(count: shots.count, box: { shots[$0].box }) { shots[$0].data }
                    fromCamera = m
                }
            }
            .fullScreenCover(item: $review) { ReviewView(model: $0) }
            .sheet(isPresented: $showSettings) { SettingsView() }
        }
    }
}

struct ItemCell: View {
    let item: Item
    let store: ImageStore
    var body: some View {
        FileImage(url: store.url(for: item.displayFile, id: item.id))
            .frame(maxWidth: .infinity).aspectRatio(4.0 / 5.0, contentMode: .fit)   // catalogue images are 1200x1500
            .background(Color(red: 244 / 255, green: 244 / 255, blue: 242 / 255))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(.quaternary))
            .overlay(alignment: .topTrailing) {
                if item.cutoutFailed {
                    Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.orange).padding(6)
                        .accessibilityLabel("Cut-out failed")
                }
            }
    }
}

extension Item {
    var snapshot: WardrobeFilter.Snapshot {
        WardrobeFilter.Snapshot(id: id, name: name, caption: caption, tags: tags, colourNames: colorNames,
                                brand: label?.brand, subBrand: label?.subBrand)
    }
}

/// Horizontal chips; each opens a multi-select menu of values that exist in the wardrobe.
struct FilterBar: View {
    @Binding var filter: WardrobeFilter
    let snaps: [WardrobeFilter.Snapshot]
    let shown: Int
    let total: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    chip("Category", $filter.categories, StyleEngine.Category.allCases.filter { c in snaps.contains { $0.tags.category == c } }, \.displayName)
                    chip("Colour", $filter.colours, ColorName.allCases.map(\.rawValue).filter { c in snaps.contains { $0.colourNames.contains(c) } },
                         { ColorName(rawValue: $0)?.displayName ?? $0 })
                    chip("Dress code", $filter.dressCodes, DressCode.allCases.filter { d in snaps.contains { $0.tags.dressCodes?.contains(d) == true } }, \.displayName)
                    chip("Season", $filter.seasons, Season.allCases.filter { x in snaps.contains { $0.tags.seasons?.contains(x) == true } }, \.displayName)
                    chip("Brand", $filter.brands, Array(Set(snaps.compactMap(\.brand))).sorted(), { $0 })
                    if filter.isActive { Button("Clear") { filter.clear() }.font(.subheadline) }
                }
            }
            if filter.isActive { Text("\(shown) of \(total) items").font(.caption).foregroundStyle(.secondary) }
        }
    }

    private func chip<V: Hashable>(_ title: String, _ sel: Binding<Set<V>>, _ options: [V], _ label: @escaping (V) -> String) -> some View {
        Menu {
            ForEach(options, id: \.self) { o in
                Toggle(label(o), isOn: Binding(get: { sel.wrappedValue.contains(o) },
                                               set: { if $0 { sel.wrappedValue.insert(o) } else { sel.wrappedValue.remove(o) } }))
            }
        } label: {
            let n = sel.wrappedValue.count
            Text(n == 0 ? title : "\(title) \(n)").font(.subheadline)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(n == 0 ? Color.secondary.opacity(0.12) : Color.accentColor.opacity(0.2), in: Capsule())
                .overlay(Capsule().stroke(n == 0 ? Color.clear : Color.accentColor))
        }
        .disabled(options.isEmpty)
    }
}
