import ImagePlayground
import StyleEngine
import SwiftUI
import WardrobeImaging

/// Settings > Developer > Templates: one canonical template image per garment shape. A saved template beats the bundled one.
struct TemplatesView: View {
    @State private var session = ProductShotSession()
    @State private var tick = 0
    @State private var message: String?
    @Environment(\.supportsImagePlayground) private var supportsImagePlayground
    private var store: TemplateStore { session.templates }

    var body: some View {
        List {
            ForEach(TemplateShape.allCases, id: \.self) { shape in
                let exists = { _ = tick; return store.url(for: shape) != nil }()
                HStack {
                    Label(shape.label, systemImage: exists ? "checkmark.circle.fill" : "circle").foregroundStyle(exists ? .primary : .secondary)
                    Spacer()
                    if supportsImagePlayground {
                        Button("Make template") {
                            Task {
                                message = nil
                                if case .failed(let e) = await session.makeTemplate(shape) { message = e }
                                tick += 1
                            }
                        }.buttonStyle(.bordered).controlSize(.small).disabled(session.isBusy)
                    }
                    if store.isSaved(shape) {
                        Button("Remove", role: .destructive) { store.remove(shape); tick += 1 }.buttonStyle(.bordered).controlSize(.small)
                    }
                }
            }
            if let m = message { Text(m).font(.footnote).foregroundStyle(.red) }
            if !supportsImagePlayground { Text(productShotUnavailableReason).font(.footnote).foregroundStyle(.secondary) }
        }
        .navigationTitle("Templates").navigationBarTitleDisplayMode(.inline)
        .productShotSheet(session)
    }
}
