import StyleEngine
import SwiftUI

/// The parsed intent as chips: `Festival · Evening · Indoor · Mild · Festive`. Each opens a picker; changing one re-runs the engine.
struct IntentChipsView: View {
    let intent: OccasionIntent
    let edit: ((inout OccasionIntent) -> Void) -> Void

    private var dressCodes: [DressCode?] { [nil] + DressCode.allCases.map { Optional($0) } }
    private var tableDressCode: DressCode? { OccasionTable.rows[intent.occasion]?.dressCodes.first }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                pick(intent.occasion.title, Occasion.allCases, \.title) { o in edit { $0 = IntentMerge.chipIntent(for: o).keeping(from: $0) } }
                pick(intent.timeOfDay.rawValue.capitalized, TimeOfDay.allCases, { $0.rawValue.capitalized }) { t in edit { $0.timeOfDay = t } }
                pick(intent.setting.rawValue.capitalized, VenueSetting.allCases, { $0.rawValue.capitalized }) { s in edit { $0.setting = s } }
                pick(intent.weatherFeel == .unknown ? "Any weather" : intent.weatherFeel.rawValue.capitalized, WeatherFeel.allCases,
                     { $0 == .unknown ? "Any weather" : $0.rawValue.capitalized }) { w in edit { $0.weatherFeel = w } }
                pick((intent.dressCode ?? tableDressCode)?.displayName ?? "Any dress code", dressCodes, { $0?.displayName ?? "Default" }) { d in edit { $0.dressCode = d } }
                Button { edit { $0.preferIndian.toggle() } } label: { chip("Indian wear", on: intent.preferIndian) }.buttonStyle(.plain)
                ForEach(intent.flags.sorted { $0.rawValue < $1.rawValue }, id: \.self) { f in
                    Button { edit { $0.flags.remove(f) } } label: { chip(flagTitle(f) + "  ✕", on: true) }.buttonStyle(.plain)
                }
                ForEach(intent.avoid, id: \.self) { a in
                    Button { edit { $0.avoid.removeAll { $0 == a } } } label: { chip("No \(avoidTitle(a))  ✕", on: true) }.buttonStyle(.plain)
                }
            }
        }
    }

    private func pick<T: Hashable>(_ current: String, _ options: [T], _ title: @escaping (T) -> String, set: @escaping (T) -> Void) -> some View {
        Menu {
            ForEach(options, id: \.self) { o in Button(title(o)) { set(o) } }
        } label: { chip(current, on: false, menu: true) }
    }

    private func chip(_ text: String, on: Bool, menu: Bool = false) -> some View {
        HStack(spacing: 3) { Text(text); if menu { Image(systemName: "chevron.down").font(.caption2) } }
            .font(.footnote.weight(.medium)).padding(.horizontal, 10).padding(.vertical, 6)
            .background(on ? Color.accentColor.opacity(0.15) : Color(.secondarySystemBackground), in: Capsule())
            .foregroundStyle(.primary)
    }

    private func flagTitle(_ f: IntentFlag) -> String {
        switch f { case .fireworks: "Fireworks"; case .lotsOfWalking: "Lots of walking"; case .religiousSite: "Religious site"; case .photoHeavy: "Photos" }
    }
    private func avoidTitle(_ a: AvoidTerm) -> String {
        switch a { case .colour(let c): c.displayName.lowercased(); case .subcategory(let s): s.displayName.lowercased() }
    }
}

private extension OccasionIntent {
    /// A new occasion from the chip keeps what the user set beside it (time, setting, weather, flags, avoid, pins).
    func keeping(from old: OccasionIntent) -> OccasionIntent {
        var i = self
        i.timeOfDay = old.timeOfDay; i.setting = old.setting; i.weatherFeel = old.weatherFeel; i.preferIndian = old.preferIndian
        i.flags = old.flags; i.avoid = old.avoid; i.mustIncludeItemIds = old.mustIncludeItemIds
        return i
    }
}
