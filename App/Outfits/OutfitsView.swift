import StyleEngine
import SwiftData
import SwiftUI

struct OutfitsView: View {
    @Environment(AppEnvironment.self) private var env
    @Query(sort: \Outfit.createdAt, order: .reverse) private var all: [Outfit]
    @Query private var rows: [OutfitItem]
    @Query private var items: [Item]
    @State private var occasion: Occasion?
    @State private var building = false

    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 12)]

    /// Saved outfits, newest first.
    static func saved(in context: ModelContext) -> [Outfit] {
        (try? context.fetch(FetchDescriptor<Outfit>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])))?.filter(\.saved) ?? []
    }
    static func filter(_ outfits: [Outfit], occasion: Occasion?) -> [Outfit] {
        guard let occasion else { return outfits }
        return outfits.filter { $0.occasion == occasion.rawValue }
    }

    private var saved: [Outfit] { all.filter(\.saved) }
    private var present: [Occasion] { Occasion.allCases.filter { o in saved.contains { $0.occasion == o.rawValue } } }

    var body: some View {
        NavigationStack {
            ScrollView {
                let byId = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
                let shown = Self.filter(saved, occasion: occasion)
                VStack(alignment: .leading, spacing: 12) {
                    if saved.isEmpty {
                        ContentUnavailableView("No saved outfits", systemImage: "rectangle.stack",
                                               description: Text("Save an outfit from the Stylist tab and it will be here."))
                            .padding(.top, 60)
                    } else {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                filterChip("All", on: occasion == nil) { occasion = nil }
                                ForEach(present, id: \.self) { o in filterChip(o.title, on: occasion == o) { occasion = o } }
                            }
                        }
                        LazyVGrid(columns: columns, spacing: 12) {
                            ForEach(shown) { o in
                                NavigationLink(value: o.id) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        if let c = o.canvas { CanvasOutfitView(canvas: c, items: byId, store: env.store) }
                                        else { OutfitCardView(slots: OutfitSaver.slots(of: o, rows: rows), items: byId, store: env.store, compact: true) }
                                        Text(o.name).font(.subheadline.weight(.medium)).lineLimit(1)
                                    }
                                }.buttonStyle(.plain)
                            }
                        }
                    }
                }.padding(16)
            }
            .navigationTitle("Outfits")
            .toolbar { ToolbarItem(placement: .primaryAction) { Button { building = true } label: { Label("New outfit", systemImage: "plus") } } }
            .fullScreenCover(isPresented: $building) { OutfitBuilderView() }
            .navigationDestination(for: UUID.self) { id in
                if let o = saved.first(where: { $0.id == id }) { OutfitDetailView(outfit: o, rows: rows, items: items) }
            }
        }
    }

    private func filterChip(_ t: String, on: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(t).font(.footnote.weight(.medium)).padding(.horizontal, 10).padding(.vertical, 6)
                .background(on ? Color.accentColor.opacity(0.15) : Color(.secondarySystemBackground), in: Capsule())
        }.buttonStyle(.plain)
    }
}
