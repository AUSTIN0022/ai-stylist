import StyleEngine
import SwiftUI

/// One block of chips on the review card.
struct TagChipGroup: Identifiable {
    let title: String
    let fields: [TagField]
    var id: String { title }

    /// What it is / How it's made / When to wear it, limited to the fields that apply to `category`:
    /// the identity fields, call B's `constructionFields(for:)`, and call C's fields.
    static func groups(for category: StyleEngine.Category) -> [TagChipGroup] {
        let made: [TagField] = [.pattern, .fabric, .fit, .length, .collar, .sleeve, .closedToe].filter { constructionFields(for: category).contains($0) }
        return [TagChipGroup(title: "What it is", fields: [.subcategory, .styleOrigin]),
                TagChipGroup(title: "How it's made", fields: made),
                TagChipGroup(title: "When to wear it", fields: [.dressCodes, .formality, .seasons, .warmth, .statement])]
    }
}

/// Wraps its children onto new lines.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(proposal.width ?? .infinity, subviews).size
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for (i, f) in arrange(bounds.width, subviews).frames.enumerated() {
            subviews[i].place(at: CGPoint(x: bounds.minX + f.minX, y: bounds.minY + f.minY), proposal: ProposedViewSize(f.size))
        }
    }
    private func arrange(_ width: CGFloat, _ subviews: Subviews) -> (frames: [CGRect], size: CGSize) {
        var x: CGFloat = 0, y: CGFloat = 0, row: CGFloat = 0, frames: [CGRect] = [], maxX: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > 0, x + s.width > width { x = 0; y += row + spacing; row = 0 }
            frames.append(CGRect(origin: CGPoint(x: x, y: y), size: s))
            x += s.width + spacing; row = max(row, s.height); maxX = max(maxX, x - spacing)
        }
        return (frames, CGSize(width: maxX, height: y + row))
    }
}

/// Every tag of one review card as compact chips. Each chip opens a menu of the allowed values only
/// (two taps); an edit is a user correction, never a change to the AI's answer.
struct TagChips: View {
    let model: ReviewModel
    let photo: ReviewModel.Photo

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            switch photo.tagState {
            case .running: HStack { ProgressView(); Text("Reading the details…").font(.footnote).foregroundStyle(.secondary) }
            case .failed(let e): Label("Tagging failed: \(e)", systemImage: "exclamationmark.triangle").font(.footnote).foregroundStyle(.orange)
            default: EmptyView()
            }
            ForEach(model.chipGroups(photo)) { g in
                VStack(alignment: .leading, spacing: 6) {
                    Text(g.title).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                    FlowLayout(spacing: 6) { ForEach(g.fields, id: \.self) { field($0) } }
                }
            }
        }
    }

    private var t: ItemTags { model.effectiveTags(photo) }
    private var id: UUID { photo.id }

    @ViewBuilder private func field(_ f: TagField) -> some View {
        switch f {
        case .subcategory:
            pick(f, "Type", t.subcategory?.displayName, t.subcategory) { v in model.setField(id, \.subcategory, to: v) }
                options: { subcategories(for: t.category ?? .top) }
        case .styleOrigin: pick(f, "Style", t.styleOrigin?.displayName, t.styleOrigin) { model.setField(id, \.styleOrigin, to: $0) } options: { StyleOrigin.allCases }
        case .pattern: pick(f, "Pattern", t.pattern?.displayName, t.pattern) { model.setField(id, \.pattern, to: $0) } options: { Pattern.allCases }
        case .fabric: pick(f, "Fabric", t.fabric?.displayName, t.fabric) { model.setField(id, \.fabric, to: $0) } options: { Fabric.allCases }
        case .fit: pick(f, "Fit", t.fit?.displayName, t.fit) { model.setField(id, \.fit, to: $0) } options: { Fit.allCases }
        case .length:
            pick(f, "Length", t.length?.displayName, t.length) { model.setField(id, \.length, to: $0) }
                options: { t.category == .bottom ? [.short, .ankle, .full] : [.cropped, .regular, .long] }
        case .collar: pick(f, "Collar", t.collar?.displayName, t.collar) { model.setField(id, \.collar, to: $0) } options: { Collar.allCases }
        case .sleeve: pick(f, "Sleeve", t.sleeve?.displayName, t.sleeve) { model.setField(id, \.sleeve, to: $0) } options: { Sleeve.allCases }
        case .statement: pick(f, "Statement", t.statement?.displayName, t.statement) { model.setField(id, \.statement, to: $0) } options: { Statement.allCases }
        case .formality:
            pick(f, "Formality", t.formality.map(String.init), t.formality) { model.setField(id, \.formality, to: $0) } options: { Array(1...5) }
        case .warmth:
            pick(f, "Warmth", t.warmth.map { ["", "Light", "Medium", "Warm"][min(max($0, 1), 3)] }, t.warmth) { model.setField(id, \.warmth, to: $0) } options: { Array(1...3) }
        case .closedToe:
            pick(f, "Toe", t.closedToe.map { $0 ? "Closed" : "Open" }, t.closedToe) { model.setField(id, \.closedToe, to: $0) } options: { [true, false] }
        case .dressCodes:
            multi(f, "Wear for", (t.dressCodes ?? []).map(\.displayName), DressCode.allCases, t.dressCodes ?? []) { model.setField(id, \.dressCodes, to: $0) }
        case .seasons:
            multi(f, "Seasons", (t.seasons ?? []).map(\.displayName), Season.allCases, t.seasons ?? []) { model.setField(id, \.seasons, to: $0) }
        case .setRole: EmptyView()
        }
    }

    private func label(_ f: TagField, _ title: String, _ value: String?) -> some View {
        HStack(spacing: 4) {
            if model.needsCheck(photo, f) { Circle().fill(.orange).frame(width: 7, height: 7).accessibilityLabel("Check this") }
            Text(title).foregroundStyle(.secondary)
            Text(value ?? "?").fontWeight(.medium)
        }
        .font(.footnote).padding(.horizontal, 10).padding(.vertical, 6).background(.quaternary, in: Capsule())
    }

    /// Single choice from the allowed values (the current one is ticked).
    private func pick<V: Hashable>(_ f: TagField, _ title: String, _ shown: String?, _ current: V?, set: @escaping (V?) -> Void,
                                   options: () -> [V]) -> some View {
        Menu {
            ForEach(options(), id: \.self) { v in
                Button { set(v) } label: { if v == current { Label(name(v), systemImage: "checkmark") } else { Text(name(v)) } }
            }
        } label: { label(f, title, shown) }
        .buttonStyle(.plain)
    }

    /// Several values (dress codes, seasons). Never empty for dress codes: the model rejects an empty set.
    private func multi<V: Hashable & Taxonomy>(_ f: TagField, _ title: String, _ shown: [String], _ all: [V], _ current: [V], set: @escaping ([V]) -> Void) -> some View {
        Menu {
            ForEach(all, id: \.self) { v in
                Toggle(v.displayName, isOn: Binding(get: { current.contains(v) },
                                                    set: { on in set(on ? current + [v] : current.filter { $0 != v }) }))
            }
        } label: { label(f, title, shown.isEmpty ? nil : shown.joined(separator: ", ")) }
        .buttonStyle(.plain)
    }

    private func name<V>(_ v: V) -> String {
        if let t = v as? any Taxonomy { return t.displayName }
        if let b = v as? Bool { return b ? "Closed" : "Open" }
        return "\(v)"
    }
}
