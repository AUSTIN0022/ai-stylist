import StyleEngine
import SwiftData
import SwiftUI

struct OutfitDetailView: View {
    @Environment(AppEnvironment.self) private var env
    let outfit: Outfit
    let rows: [OutfitItem]
    let items: [Item]
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var renaming = false
    @State private var newName = ""
    @State private var confirmDelete = false
    @State private var editingLayout = false
    @State private var wornOn = Date()
    @State private var askWornDate = false
    @Query private var wearLogs: [WearLog]

    var body: some View {
        let byId = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let slots = OutfitSaver.slots(of: outfit, rows: rows)
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let c = outfit.canvas { CanvasOutfitView(canvas: c, items: byId, store: env.store) }
                else { OutfitCardView(slots: slots, items: byId, store: env.store, note: outfit.note) }
                if outfit.canvas != nil, let n = outfit.note { Text(n).font(.footnote).foregroundStyle(.secondary) }
                HStack {
                    Button("Mark worn today", systemImage: "checkmark.circle") { WearLogger.markWorn(itemIds: Array(slots.values), outfitId: outfit.id, on: .now, in: context) }
                        .buttonStyle(.borderedProminent)
                    Button("Another day…", systemImage: "calendar") { askWornDate = true }.buttonStyle(.bordered)
                }
                let dates = wearLogs.filter { $0.outfitId == outfit.id }.map(\.date).sorted(by: >)
                if !dates.isEmpty {
                    Text("Worn: " + dates.map { $0.formatted(date: .abbreviated, time: .omitted) }.joined(separator: ", ")).font(.footnote).foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(slots.sorted { $0.key < $1.key }, id: \.key) { slot, id in
                        if let item = byId[id] {
                            NavigationLink { ItemDetailView(item: item) } label: {
                                HStack { Text(slotName(slot).capitalized).foregroundStyle(.secondary); Spacer(); Text(item.name); Image(systemName: "chevron.right").font(.caption) }
                                    .padding(.vertical, 10)
                            }.buttonStyle(.plain)
                            Divider()
                        }
                    }
                }
            }.padding(16)
        }
        .navigationTitle(outfit.name).navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("Edit layout", systemImage: "square.and.pencil") { editingLayout = true }
                    Button("Rename", systemImage: "pencil") { newName = outfit.name; renaming = true }
                    Button("Delete", systemImage: "trash", role: .destructive) { confirmDelete = true }
                } label: { Image(systemName: "ellipsis.circle") }
            }
        }
        .fullScreenCover(isPresented: $editingLayout) { OutfitBuilderView(editing: outfit, start: OutfitSaver.canvas(for: outfit, rows: rows)) }
        .sheet(isPresented: $askWornDate) {
            NavigationStack {
                DatePicker("Worn on", selection: $wornOn, in: ...Date.now, displayedComponents: .date).datePickerStyle(.graphical).padding()
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) { Button("Cancel") { askWornDate = false } }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Mark worn") { WearLogger.markWorn(itemIds: Array(slots.values), outfitId: outfit.id, on: wornOn, in: context); askWornDate = false }
                        }
                    }
            }.presentationDetents([.medium])
        }
        .alert("Rename outfit", isPresented: $renaming) {
            TextField("Name", text: $newName)
            Button("Save") {
                let n = newName.trimmingCharacters(in: .whitespacesAndNewlines)
                if !n.isEmpty { outfit.name = n; try? context.save() }
            }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("Delete this outfit? Your clothes stay in the wardrobe.", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { dismiss(); OutfitSaver.delete(outfit, in: context) }
        }
    }
}
