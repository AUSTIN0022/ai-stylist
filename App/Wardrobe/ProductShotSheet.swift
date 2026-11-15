import ImagePlayground
import StyleEngine
import SwiftUI

/// Presents Image Playground for a `ProductShotSession`: concepts = prompt text + fabric swatch image, sourceImage = cut-out on white,
/// style locked to `.any`. Attach to a view that stays on screen while the sheet is up.
private struct ProductShotSheet: ViewModifier {
    @Bindable var session: ProductShotSession
    @AppStorage(ProductPromptStyle.key) private var style = ProductPromptStyle.proven.rawValue
    /// Device test (14 Nov): one long sentence was refused ("Try describing something different"), so the default is short phrases.
    /// The other styles stay selectable in Settings > Developer to compare on the phone.
    private var concepts: [ImagePlaygroundConcept] {
        let swatch = session.swatch.map { [ImagePlaygroundConcept.image($0)] } ?? []
        switch ProductPromptStyle(rawValue: style) ?? .proven {
        case .proven: return [.text(session.sentence)]
        case .provenSwatch: return [.text(session.sentence)] + swatch
        case .short: return session.shortConcepts.map { .text($0) } + swatch
        case .shortNoSwatch: return session.shortConcepts.map { .text($0) }
        case .extracted: return [.extracted(from: session.prompt, title: session.title)] + swatch
        }
    }
    /// Portrait 4:5 output (the catalogue canvas); keep the source image's layout when there is one.
    private var options: ImagePlaygroundOptions {
        var o = ImagePlaygroundOptions()
        o.sizeSpecification = .closest(to: CGSize(width: 1200, height: 1500))
        o.creationStrategy = session.sourceImage == nil ? .automatic : .editExisting
        return o
    }
    func body(content: Content) -> some View {
        content
            .imagePlaygroundGenerationStyle(.any, in: [.any])
            .imagePlaygroundOptions(options)
            .imagePlaygroundSheet(isPresented: $session.isPresented, concepts: concepts,
                                  sourceImage: session.sourceImage.map { Image(decorative: $0, scale: 1) },
                                  onCompletion: { session.deliver($0) }, onCancellation: { session.cancel() })
            .confirmationDialog("Sleeve length?", isPresented: Binding(get: { session.askingSleeve }, set: { if !$0 { session.answerSleeve(nil) } }), titleVisibility: .visible) {
                ForEach(Sleeve.allCases, id: \.self) { sl in Button(sl.displayName) { session.answerSleeve(sl) } }
            } message: { Text("Image Playground needs it to draw the right sleeves.") }
            .onChange(of: session.isPresented) { _, shown in if !shown { session.cancel() } }
    }
}

enum ProductPromptStyle: String, CaseIterable, Identifiable {
    case proven, provenSwatch, short, shortNoSwatch, extracted
    static let key = "productPromptStyle"
    var id: String { rawValue }
    var label: String {
        switch self {
        case .proven: "Proven sentence (default)"
        case .provenSwatch: "Proven sentence + fabric swatch"
        case .short: "Short phrases + fabric swatch"
        case .shortNoSwatch: "Short phrases only"
        case .extracted: "Long description (Apple extracts)"
        }
    }
}

extension View {
    func productShotSheet(_ session: ProductShotSession) -> some View { modifier(ProductShotSheet(session: session)) }
}

/// One-line reason shown instead of the product-photo buttons.
let productShotUnavailableReason = "Product photos need Apple Intelligence with Image Playground on this iPhone."


/// Dim + sparkle shimmer over the item image while the product photo is being prepared or saved. Reduce Motion: static dim + spinner.
struct ProductShotOverlay: View {
    let state: ProductShotSession.Overlay
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var sweep = false

    private var text: String? { state == .preparing ? "Preparing…" : state == .saving ? "Saving…" : nil }

    var body: some View {
        if let text {
            ZStack {
                Rectangle().fill(.black.opacity(0.35))
                if reduceMotion {
                    VStack(spacing: 10) { ProgressView().tint(.white); Label(text, systemImage: "sparkles") }
                } else {
                    Rectangle()
                        .fill(LinearGradient(colors: [.clear, .white.opacity(0.45), .clear], startPoint: .leading, endPoint: .trailing))
                        .containerRelativeFrame(.horizontal) { w, _ in w * 0.5 }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .offset(x: sweep ? 400 : -400)
                        .onAppear { withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) { sweep = true } }
                    VStack(spacing: 8) {
                        Image(systemName: "sparkles").font(.largeTitle).symbolEffect(.variableColor.iterative.reversing)
                        Text(text)
                    }
                }
            }
            .foregroundStyle(.white).font(.headline)
            .clipped().allowsHitTesting(false)
            .accessibilityElement(children: .ignore).accessibilityLabel(text)
            .transition(.opacity)
        }
    }
}
