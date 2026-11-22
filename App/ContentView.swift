import SwiftData
import SwiftUI
import WardrobeImaging

struct ContentView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        TabView {
            WardrobeView().tabItem { Label("Wardrobe", systemImage: "tshirt") }
            StylistView().tabItem { Label("Stylist", systemImage: "sparkles") }
            OutfitsView().tabItem { Label("Outfits", systemImage: "rectangle.stack") }
        }
        // Runs once at launch, before any review can start, so in-progress photos are never touched.
        .task {
            // Fetch explicitly: if the fetch fails, delete nothing.
            guard let items = try? context.fetch(FetchDescriptor<Item>()) else { return }
            env.store.removeOrphans(keeping: Set(items.map(\.id)))
            // Build any missing outfit stickers in the background, one at a time, so no card waits for a cut-out when it is first opened.
            let (ids, store) = (items.map(\.id), env.store)
            Task.detached(priority: .utility) { await StickerMaker.prewarm(ids: ids, store: store, cutout: VisionCutoutService()) }
        }
    }
}
