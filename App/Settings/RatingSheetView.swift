import StyleEngine
import SwiftData
import SwiftUI

/// Settings > Rate the engine: the ten SPRINT_6 requests on your real wardrobe, the top three each. Mark each W (would wear) or
/// N (wouldn't, with a one-word reason). Two rounds are kept apart: before tuning and after. Export the table for `docs/EVAL_MVP.md`.
struct RatingSheetView: View {
    @Environment(AppEnvironment.self) private var env
    @Query private var items: [Item]
    @State private var round = Round.before
    @State private var rows: [RatingSheet.Row] = []
    @State private var slots: [[[Slot: UUID]]] = []      // per request, per outfit
    @State private var copied = false

    enum Round: String, CaseIterable, Identifiable { case before = "Before tuning", after = "After tuning"; var id: String { rawValue } }
    private var key: String { "ratingSheet.\(round.rawValue)" }
    private var byId: [UUID: Item] { Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a }) }
    private var markdown: String { RatingSheet.markdown(rows, round: round.rawValue, date: Date.now.formatted(.iso8601.year().month().day())) }

    var body: some View {
        List {
            Section {
                Picker("Round", selection: $round) { ForEach(Round.allCases) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented)
                Text("\(RatingSheet.passed(rows)) of \(rows.count) occasions pass (2 of 3 wearable). Goal: all 10 after tuning.").font(.footnote)
                Button(copied ? "Copied" : "Copy table", systemImage: copied ? "checkmark" : "doc.on.doc") { UIPasteboard.general.string = markdown; copied = true }
            }
            ForEach(rows.indices, id: \.self) { r in
                Section(header: Text("\(r + 1). \(rows[r].title)")) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(alignment: .top, spacing: 10) {
                            ForEach(rows[r].outfits.indices, id: \.self) { o in outfit(r, o) }
                        }
                    }
                    HStack { Text("Wearable \(rows[r].wearable)/3"); Spacer(); Image(systemName: rows[r].passes ? "checkmark.circle.fill" : rows[r].isComplete ? "xmark.circle.fill" : "circle").foregroundStyle(rows[r].passes ? .green : .secondary) }.font(.footnote)
                }
            }
        }
        .navigationTitle("Rate the engine").navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: generate).onChange(of: round) { _, _ in generate() }
        .onChange(of: rows) { _, new in if let d = try? JSONEncoder().encode(new) { UserDefaults.standard.set(d, forKey: key) } }
    }

    @ViewBuilder private func outfit(_ r: Int, _ o: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            OutfitCardView(slots: slots[r][o], items: byId, store: env.store, compact: true).frame(width: 190)
            Text(rows[r].outfits[o].description).font(.caption2).foregroundStyle(.secondary).lineLimit(3).frame(width: 190, alignment: .leading)
            HStack {
                rateButton("W", .wear, r, o); rateButton("N", .wouldNot, r, o)
            }
            if rows[r].outfits[o].rating == .wouldNot {
                TextField("one-word reason", text: Binding(get: { rows[r].outfits[o].reason }, set: { rows[r].outfits[o].reason = $0 }))
                    .textFieldStyle(.roundedBorder).font(.caption).frame(width: 190)
            }
        }
    }

    private func rateButton(_ label: String, _ value: Rating, _ r: Int, _ o: Int) -> some View {
        let on = rows[r].outfits[o].rating == value
        return Button(label) { rows[r].outfits[o].rating = on ? nil : value }
            .buttonStyle(.borderedProminent).tint(on ? (value == .wear ? .green : .red) : .gray).controlSize(.small)
    }

    /// Runs the engine for every request on today's wardrobe (fixed seed, so the two rounds differ only by tuning), then restores saved ratings.
    private func generate() {
        let engineItems = items.filter { $0.status == .ready }.map(\.engineItem)
        let saved = (UserDefaults.standard.data(forKey: key).flatMap { try? JSONDecoder().decode([RatingSheet.Row].self, from: $0) }) ?? []
        var newRows: [RatingSheet.Row] = [], newSlots: [[[Slot: UUID]]] = []
        for req in RatingSheet.requests {
            let res = OutfitEngine.generate(intent: req.intent, items: engineItems, context: RatingSheet.context)
            let old = saved.first { $0.title == req.title }?.outfits ?? []
            newRows.append(.init(title: req.title, outfits: res.outfits.map { c in
                let d = c.describe(items: engineItems)
                let prev = old.first { $0.description == d }
                return RatingSheet.Entry(description: d, rating: prev?.rating, reason: prev?.reason ?? "")
            }))
            newSlots.append(res.outfits.map(\.slots))
        }
        slots = newSlots; rows = newRows
    }
}
