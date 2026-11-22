import Foundation
import Observation
import StyleEngine
import SwiftData
import WardrobeImaging

extension Item {
    /// The engine's input: effective tags and colours, ready only when tagging finished.
    var engineItem: EngineItem {
        var t = tags
        if setGroupId != nil { t.setRole = setRole }          // a set linked by hand: its role wins over the AI's
        return EngineItem(id: id, name: name, tags: t, colors: colorNames.compactMap(ColorName.init(rawValue:)),
                   setGroupId: setGroupId, lastWornAt: lastWornAt, isReady: status == .ready)
    }
}

extension Occasion {
    var title: String {
        switch self {
        case .casualDay: "Casual"
        case .weddingGuest: "Wedding"
        case .puja: "Puja"
        default: rawValue.prefix(1).uppercased() + rawValue.dropFirst()
        }
    }
}

/// Stylist tab state (Sprint 4): current intent, the session (shown keys, outfits), notes, selection for swap.
/// Cards come straight from the engine; notes fill in later and never block them.
@MainActor @Observable final class StylistViewModel {
    private(set) var intent: OccasionIntent?
    private(set) var session = StylistSession()
    private(set) var notes: [UUID: String] = [:]
    private(set) var savedIds: Set<UUID> = []
    private(set) var lastMessage: String?
    private(set) var isThinking = false
    private(set) var errorMessage: String?          // nothing sets this today: a failed note or parse is never an error to the user
    private(set) var notesTask: Task<Void, Never>?
    var selection: (outfit: UUID, slot: Slot)?
    private(set) var swapOptions: [OutfitCandidate] = []

    let today: Date
    let store: ImageStore
    private let parser: IntentParser, writer: NoteWriter, context: ModelContext
    private let weather: TodaysWeather?
    /// Today's weather (Sprint 6), once known: the default `weatherFeel` when the user's words say nothing about it.
    private(set) var todaysWeather: WeatherFeel = .unknown
    private var recent: [String] = []               // user messages, last three
    private var swapped: Set<UUID> = []             // outfits whose note no longer matches their items

    init(parser: IntentParser, writer: NoteWriter, context: ModelContext, store: ImageStore = .standard, today: Date = .now,
         weather: TodaysWeather? = nil) {
        self.parser = parser; self.writer = writer; self.context = context; self.store = store; self.today = today; self.weather = weather
    }

    /// One cached request per day, never throws; `unknown` when it cannot be had. Cheap to call again. The Stylist tab calls it when it
    /// opens, so a request never waits on the location prompt or the network.
    func refreshWeather() async {
        guard let weather else { return }
        todaysWeather = await weather.feel(on: today)
    }

    /// The first intent of a session gets today's weather when it names none. Later ones keep what the user set (including "Any weather").
    private func defaulted(_ i: OccasionIntent, previous: OccasionIntent?) -> OccasionIntent {
        guard previous == nil, i.weatherFeel == .unknown else { return i }
        var i = i; i.weatherFeel = todaysWeather; return i
    }

    static func live(_ env: AppEnvironment, context: ModelContext) -> StylistViewModel {
        StylistViewModel(parser: env.provider.makeIntentParser(), writer: env.provider.makeNoteWriter(), context: context, store: env.store,
                         weather: env.weather)
    }

    var outfits: [ShownOutfit] { session.outfits }
    var state: StylistSession.State { session.state }
    /// Slots the shown outfits are built without (footwear): the screen says what to add.
    var softMissing: [Slot] { session.softMissing }

    /// Saved in this session, or the same item set is already in the store (it was shown again later).
    func isSaved(_ id: UUID) -> Bool {
        if savedIds.contains(id) { return true }
        guard let o = outfits.first(where: { $0.id == id }) else { return false }
        return OutfitSaver.existing(slots: o.candidate.slots, in: context) != nil
    }

    // MARK: Items

    private func allItems() -> [Item] { (try? context.fetch(FetchDescriptor<Item>())) ?? [] }
    private func engineItems() -> [EngineItem] { allItems().map(\.engineItem) }
    func item(_ id: UUID) -> Item? { allItems().first { $0.id == id } }

    // MARK: Requests

    /// Typed message: one AI call for the intent (fresh text-only session), then the engine. Falls back to casual-day
    /// defaults (or the previous intent) when the parser fails, so the chips still show and can be set by hand.
    func send(_ text: String) async {
        let message = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty, !isThinking else { return }
        isThinking = true; defer { isThinking = false }
        lastMessage = message
        let prev = intent, before = Array(recent.suffix(2))
        recent = Array((recent + [message]).suffix(3))
        do {
            let parsed = try await AICall.record(purpose: "intent", provider: loggedProvider(of: parser), model: parser.version, tokens: { [parser] in (parser as? TokenReporting)?.lastTokenCount },
                                             sink: { await self.log($0) }) { try await parser.parse(message: message, previous: prev, recent: before) }
            intent = defaulted(parsed, previous: prev)
        } catch {
            intent = prev ?? defaulted(IntentMerge.chipIntent(for: .casualDay), previous: nil)
        }
        run()
    }

    /// Occasion chip: the table's intent, no AI.
    func choose(_ o: Occasion) { lastMessage = nil; intent = defaulted(IntentMerge.chipIntent(for: o), previous: intent); run() }

    /// Intent chip edit: new intent, shown keys cleared, no AI.
    func edit(_ change: (inout OccasionIntent) -> Void) {
        guard var i = intent else { return }
        change(&i); intent = i; run()
    }

    func pin(_ itemId: UUID) { guard let i = intent else { return }; intent = IntentMerge.pin(itemId, in: i); run() }

    func startOver() {
        notesTask?.cancel(); session = StylistSession(); intent = nil; notes = [:]; lastMessage = nil; recent = []
        selection = nil; swapOptions = []; swapped = []
    }

    private func run() {
        guard let intent else { return }
        resetOutfitState()
        session.pairWeights = Learning.pairWeights(in: context)
        session.start(intent: intent, items: engineItems(), today: today)
        fillNotes()
    }

    func anotherOption() {
        guard let intent else { return }
        let old = session.another(intent: intent, items: engineItems(), today: today)
        guard !old.isEmpty else { return }          // exhausted: state says so, old outfits stay
        for o in old { context.insert(FeedbackEvent(outfitId: o.id, action: "rejected", itemIds: o.candidate.itemIds)) }
        try? context.save()
        resetOutfitState()
        fillNotes()
    }

    private func resetOutfitState() { notesTask?.cancel(); notes = [:]; selection = nil; swapOptions = []; swapped = [] }

    // MARK: Swap

    func select(outfit: UUID, slot: Slot) {
        guard let intent else { return }
        selection = (outfit, slot)
        swapOptions = session.alternatives(for: outfit, slot: slot, intent: intent, items: engineItems(), today: today)
    }

    /// Replaces the selected slot's item with the one in `alt`. The note is dropped: it described the old item.
    func swap(to alt: OutfitCandidate) {
        guard let (id, slot) = selection, let new = alt.slots[slot] else { return }
        let before = outfits.first { $0.id == id }?.candidate.slots ?? [:]
        session.swap(id, slot: slot, to: new)
        notes[id] = nil; swapped.insert(id); savedIds.remove(id)      // new item set: a different outfit
        context.insert(FeedbackEvent(outfitId: id, action: "swapped", slot: slot.rawValue,
                                     itemIds: before.filter { $0.key != slot }.map(\.value), removedItemId: before[slot], addedItemId: new))
        try? context.save()
        selection = nil; swapOptions = []
    }

    // MARK: Save

    @discardableResult func save(_ id: UUID) -> Bool {
        guard !isSaved(id), let o = outfits.first(where: { $0.id == id }) else { return false }
        OutfitSaver.save(id: id, slots: o.candidate.slots, occasion: intent?.occasion, note: notes[id], in: context)
        savedIds.insert(id)
        return true
    }

    // MARK: Notes

    private func log(_ r: AICallRecord) async { context.insert(AIRequestLog(r)); try? context.save() }

    /// One call for the whole result set, after the cards are already on screen.
    private func fillNotes() {
        let shown = outfits
        guard let intent, !shown.isEmpty else { return }
        let byId = Dictionary(allItems().map { ($0.id, $0.engineItem) }, uniquingKeysWith: { a, _ in a })
        func rows(_ o: ShownOutfit) -> [(Slot, EngineItem)] { o.candidate.slots.sorted { $0.key < $1.key }.compactMap { s, id in byId[id].map { (s, $0) } } }
        let prompt = NotePrompt.text(intent: intent, outfits: shown.map(rows))
        let (writer, version) = (self.writer, self.writer.version)
        notesTask = Task {
            do {
                let texts = try await AICall.record(purpose: "note", provider: loggedProvider(of: writer), model: version, tokens: { (writer as? TokenReporting)?.lastTokenCount },
                                                    sink: { await self.log($0) }) { try await writer.notes(prompt: prompt, count: shown.count) }
                guard !Task.isCancelled else { return }
                for (o, text) in zip(shown, texts) where !swapped.contains(o.id) && outfits.contains(where: { $0.id == o.id }) {
                    // A note that names something outside its outfit is dropped; the card stays without one.
                    if NoteValidator.isValid(text, for: rows(o).map(\.1)) { notes[o.id] = text }
                }
            } catch { /* no note, no error */ }
        }
    }
}
