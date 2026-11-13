import SwiftData
import SwiftUI
import WardrobeImaging

struct ContentView: View {
    @Environment(\.modelContext) private var context

    var body: some View {
        TabView {
            WardrobeView().tabItem { Label("Wardrobe", systemImage: "tshirt") }
            placeholder("Stylist", "Outfit suggestions arrive in a later sprint.", "sparkles")
                .tabItem { Label("Stylist", systemImage: "sparkles") }
            placeholder("Outfits", "Saved outfits will live here.", "rectangle.stack")
                .tabItem { Label("Outfits", systemImage: "rectangle.stack") }
        }
        // Runs once at launch, before any review can start, so in-progress photos are never touched.
        .task {
            // Fetch explicitly: if the fetch fails, delete nothing.
            guard let items = try? context.fetch(FetchDescriptor<Item>()) else { return }
            ImageStore.standard.removeOrphans(keeping: Set(items.map(\.id)))
        }
    }

    private func placeholder(_ title: String, _ text: String, _ icon: String) -> some View {
        NavigationStack {
            ContentUnavailableView(title, systemImage: icon, description: Text(text)).navigationTitle(title)
        }
    }
}
