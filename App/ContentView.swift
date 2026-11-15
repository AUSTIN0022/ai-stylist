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
        }
    }
}
