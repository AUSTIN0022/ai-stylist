import StyleEngine
import SwiftUI

/// Edits label values with constrained inputs: size from a list, brand with suggestions. Used by the review and item detail.
/// Barcode and composition are shown, not editable.
struct LabelEditor: View {
    let initial: LabelData
    let pastBrands: [String]
    var onConfirm: (LabelData) -> Void
    var onCancel: () -> Void

    @State private var data: LabelData
    @State private var sizeChoice: String
    @State private var otherSize: String
    @State private var mrp: Double?
    @State private var sale: Double?
    private static let other = "Other…"

    init(initial: LabelData, pastBrands: [String], onConfirm: @escaping (LabelData) -> Void, onCancel: @escaping () -> Void) {
        self.initial = initial; self.pastBrands = pastBrands; self.onConfirm = onConfirm; self.onCancel = onCancel
        _data = State(initialValue: initial)
        _mrp = State(initialValue: initial.mrp); _sale = State(initialValue: initial.salePrice)
        let s = initial.size ?? ""
        _sizeChoice = State(initialValue: s.isEmpty || LabelOptions.sizes.contains(s) ? s : Self.other)
        _otherSize = State(initialValue: LabelOptions.sizes.contains(s) ? "" : s)
    }

    private var brand: Binding<String> { Binding(get: { data.brand ?? "" }, set: { data.brand = $0.isEmpty ? nil : $0 }) }
    /// Picking a suggestion sets brand and sub-brand together.
    private func pick(_ suggestion: String) { let r = LabelOptions.split(suggestion); data.brand = r.brand; data.subBrand = r.subBrand }
    private func text(_ kp: WritableKeyPath<LabelData, String?>) -> Binding<String> {
        Binding(get: { data[keyPath: kp] ?? "" }, set: { data[keyPath: kp] = $0.isEmpty ? nil : $0 })
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Brand (add if unknown)", text: brand)
                    let tips = LabelOptions.brandSuggestions(for: data.brand ?? "", past: pastBrands)
                        .filter { LabelOptions.split($0) != (data.brand ?? "", data.subBrand) }.prefix(5)
                    TextField("Sub-brand (optional)", text: text(\.subBrand))
                    if !(data.brand ?? "").isEmpty || !tips.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack { ForEach(Array(tips), id: \.self) { b in Button(b) { pick(b) }.buttonStyle(.bordered).controlSize(.small) } }
                        }
                    }
                }
                Picker("Fabric", selection: $data.fabric) {
                    Text("Not set").tag(Fabric?.none)
                    ForEach(Fabric.allCases, id: \.self) { Text($0.displayName).tag(Optional($0)) }
                }
                Picker("Fit", selection: $data.fit) {
                    Text("Not set").tag(Fit?.none)
                    ForEach(Fit.allCases, id: \.self) { Text($0.displayName).tag(Optional($0)) }
                }
                Picker("Size", selection: $sizeChoice) {
                    Text("Not set").tag("")
                    ForEach(LabelOptions.sizes, id: \.self) { Text($0).tag($0) }
                    Text(Self.other).tag(Self.other)
                }
                if sizeChoice == Self.other {
                    TextField("Size", text: $otherSize).textInputAutocapitalization(.characters)
                }
                TextField("MRP ₹", value: $mrp, format: .number).keyboardType(.decimalPad)
                TextField("Sale price ₹", value: $sale, format: .number).keyboardType(.decimalPad)
                TextField("Colour (as printed)", text: text(\.colour))
                TextField("Style code", text: text(\.styleCode)).textInputAutocapitalization(.characters)
                if let b = data.barcode { LabeledContent("Barcode", value: b) }
                if let c = data.composition, !c.isEmpty {
                    LabeledContent("Composition", value: c.map { "\($0.percent)% \($0.fibre)" }.joined(separator: ", "))
                }
                if let raw = data.rawText, !raw.isEmpty {
                    DisclosureGroup("Text read") { Text(raw).font(.footnote.monospaced()).frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled) }
                }
            }
            .navigationTitle("Label").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel", action: onCancel) }
                ToolbarItem(placement: .confirmationAction) { Button("Use", action: confirm) }
            }
        }
    }

    private func confirm() {
        var d = data
        d.mrp = mrp; d.salePrice = sale
        let o = otherSize.trimmingCharacters(in: .whitespaces).uppercased()
        d.size = sizeChoice == Self.other ? (o.isEmpty ? nil : o) : (sizeChoice.isEmpty ? nil : sizeChoice)
        onConfirm(d)
    }
}
