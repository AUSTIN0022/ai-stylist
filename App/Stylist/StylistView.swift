import StyleEngine
import SwiftData
import SwiftUI
import WardrobeImaging

struct StylistView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppEnvironment.self) private var env
    @Query private var items: [Item]
    @State private var vm: StylistViewModel?
    @State private var text = ""
    @FocusState private var focused: Bool

    private let chips: [Occasion] = [.office, .date, .festival, .weddingGuest, .party, .travel, .casualDay]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(chips, id: \.self) { o in
                            Button(o.title) { vm?.choose(o) }.buttonStyle(.bordered).controlSize(.small)
                        }
                    }.padding(.horizontal, 16).padding(.vertical, 8)
                }
                Divider()
                ScrollView { if let vm { conversation(vm) } }.scrollDismissesKeyboard(.interactively)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) { inputBar }          // always visible, above the tab bar and the keyboard
            .navigationTitle("Stylist").navigationBarTitleDisplayMode(.inline)
            .onAppear { if vm == nil { vm = .live(env, context: context) } }
        }
    }

    private var inputBar: some View {
        let empty = text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || vm?.isThinking == true
        return HStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles").foregroundStyle(.tint)
                TextField("Describe the occasion, e.g. Diwali dinner at a friend's", text: $text, axis: .vertical)
                    .focused($focused).lineLimit(1...3).submitLabel(.send).onSubmit { send() }
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 22))
            .overlay(RoundedRectangle(cornerRadius: 22).stroke(.tertiary))
            Button { send() } label: { Image(systemName: "arrow.up.circle.fill").font(.system(size: 40)) }
                .disabled(empty).accessibilityLabel("Send")
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(.bar)
    }

    private func send() {
        let t = text; text = ""; focused = false
        Task { await vm?.send(t) }
    }

    @ViewBuilder private func conversation(_ vm: StylistViewModel) -> some View {
        let byId = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        VStack(alignment: .leading, spacing: 14) {
            if let m = vm.lastMessage {
                Text(m).padding(10).background(Color.accentColor.opacity(0.15), in: RoundedRectangle(cornerRadius: 12))
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            if let intent = vm.intent { IntentChipsView(intent: intent) { vm.edit($0) } }
            if vm.isThinking { ProgressView("Reading your message…") }
            if vm.intent == nil && !vm.isThinking {
                ContentUnavailableView("Ask your stylist", systemImage: "sparkles",
                                       description: Text("Pick an occasion above, or describe it: \"Diwali at a friend's, evening\"."))
                    .padding(.top, 40)
            }
            ForEach(vm.outfits) { o in OutfitRow(vm: vm, outfit: o, items: byId) }
            if !vm.outfits.isEmpty, vm.softMissing.contains(.footwear) {
                Label("Add shoes to complete these looks", systemImage: "shoe").font(.footnote).foregroundStyle(.secondary)
            }
            if case .exhausted(let missing) = vm.state { exhausted(vm, missing) }
            if !vm.outfits.isEmpty || vm.intent != nil {
                HStack {
                    Button("Another option") { vm.anotherOption() }.buttonStyle(.borderedProminent).disabled(vm.intent == nil)
                    Button("Start over") { vm.startOver() }.buttonStyle(.bordered)
                }
            }
        }.padding(16)
    }

    private func exhausted(_ vm: StylistViewModel, _ missing: [Slot]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(vm.outfits.isEmpty ? "Nothing for this yet" : "That's everything your wardrobe has for this").font(.headline)
            if !missing.isEmpty { Text("Missing: " + missing.map(slotName).joined(separator: ", ")).foregroundStyle(.secondary) }
            if vm.outfits.isEmpty, vm.intent?.dressCode != nil || vm.intent?.formalityMin != nil {
                Button("Relax the dress code") { vm.edit { $0.dressCode = nil; $0.formalityMin = nil; $0.formalityMax = nil } }.buttonStyle(.bordered)
            }
        }.padding(12).frame(maxWidth: .infinity, alignment: .leading).background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
    }
}

func slotName(_ s: Slot) -> String {
    switch s {
    case .top, .setTop: "top"
    case .baseLayer: "base layer"
    case .bottom, .setBottom: "bottom"
    case .onePiece: "one-piece"
    case .outerwear: "outerwear"
    case .footwear: "footwear"
    case .accessory1, .accessory2: "accessory"
    case .setDrape: "dupatta"
    }
}

private struct OutfitRow: View {
    let vm: StylistViewModel
    let outfit: ShownOutfit
    let items: [UUID: Item]
    @State private var stripOpen = false

    private var selected: Slot? { vm.selection?.outfit == outfit.id ? vm.selection?.slot : nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            OutfitCardView(slots: outfit.candidate.slots, items: items, store: vm.store, note: vm.notes[outfit.id], selected: selected) { slot in
                stripOpen = false; vm.select(outfit: outfit.id, slot: slot)
            }
            HStack {
                if vm.isSaved(outfit.id) { Label("Saved", systemImage: "checkmark.circle.fill").foregroundStyle(.green) }
                else { Button("Save") { vm.save(outfit.id) }.buttonStyle(.bordered) }
                if let s = selected { Button("Swap \(slotName(s))") { stripOpen.toggle() }.buttonStyle(.bordered) }
            }
            if selected != nil, stripOpen {
                if vm.swapOptions.isEmpty { Text("No other options for this slot.").font(.footnote).foregroundStyle(.secondary) }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(vm.swapOptions.enumerated()), id: \.offset) { _, alt in
                            if let slot = selected, let id = alt.slots[slot], let item = items[id] {
                                Button { vm.swap(to: alt); stripOpen = false } label: { ItemCell(item: item, store: vm.store).frame(width: 72) }.buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
        }
    }
}
