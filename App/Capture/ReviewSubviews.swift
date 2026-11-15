import StyleEngine
import SwiftUI
import WardrobeImaging

// Subviews of ReviewView: progress screen, cut-out preview, tap-to-pick, adjust sheet, label chips.

/// One screen while every photo is cut out and read by the AI; the review opens when all are done (or timed out).
struct AnalysisProgress: View {
    let model: ReviewModel
    var body: some View {
        VStack(spacing: 20) {
            ProgressView(value: Double(model.settledCount), total: Double(max(1, model.photos.count)))
            Text("Cutting out and reading your clothes…").font(.headline).multilineTextAlignment(.center)
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(model.photos.enumerated()), id: \.element.id) { i, p in
                        HStack {
                            Text("Item \(i + 1)")
                            Spacer()
                            Text(model.stage(p)).foregroundStyle(.secondary)
                            if model.stage(p).hasPrefix("Done") { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green) } else if p.status != .failed { ProgressView() }
                        }.font(.subheadline)
                    }
                }
            }
        }.padding(24).frame(maxHeight: .infinity, alignment: .top)
    }
}

/// Cut-out on white with an original toggle.
struct CutoutPreview: View {
    let store: ImageStore
    let processed: ProcessedImages
    @State private var original = false
    var body: some View {
        VStack(spacing: 8) {
            FileImage(url: store.url(for: original ? processed.originalFile : processed.displayFile, id: processed.itemID), maxPixel: 1024)
                .frame(maxWidth: .infinity).aspectRatio(original ? 3 / 4 : 1, contentMode: .fit)
                .background(.white).clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(.quaternary))
            Picker("View", selection: $original) { Text("Cut-out").tag(false); Text("Original").tag(true) }
                .pickerStyle(.segmented)
        }
    }
}

/// The original with candidate bounds outlined: one tap re-cuts (review of an unclear photo).
struct CutoutPicker: View {
    let model: ReviewModel
    let photo: ReviewModel.Photo
    @State private var image: CGImage?

    var body: some View {
        let pr = photo.processed!
        VStack(spacing: 10) {
            if let image {
                let aspect = CGFloat(image.width) / CGFloat(image.height)
                Image(decorative: image, scale: 1).resizable().scaledToFit()
                    .overlay {
                        GeometryReader { geo in
                            ZStack(alignment: .topLeading) {
                                ForEach(pr.cutoutResult?.candidates ?? [], id: \.index) { c in
                                    Rectangle().stroke(Color.yellow, lineWidth: 2)
                                        .frame(width: c.bounds.width * geo.size.width, height: c.bounds.height * geo.size.height)
                                        .offset(x: c.bounds.minX * geo.size.width, y: c.bounds.minY * geo.size.height)
                                }
                            }
                            .contentShape(Rectangle())
                            .onTapGesture { loc in Task { await model.recut(photo.id, .tap(CGPoint(x: loc.x / geo.size.width, y: loc.y / geo.size.height))) } }
                        }
                    }
                    .aspectRatio(aspect, contentMode: .fit)
                    .accessibilityLabel("Original photo. Tap the item.")
            } else { ProgressView().frame(height: 300) }
        }
        .task {
            let u = model.store.url(for: pr.originalFile, id: pr.itemID)
            image = await Task.detached { ImageCodec.thumbnail(at: u, maxPixel: 1024) }.value
        }
    }
}

struct AdjustSheet: View {
    let model: ReviewModel
    let id: UUID
    @Environment(\.dismiss) private var dismiss
    @State private var image: CGImage?
    var body: some View {
        NavigationStack {
            Group {
                if let p = model.photo(id), let pr = p.processed {
                    if let image, let res = pr.cutoutResult {
                        AdjustCanvas(image: image, candidates: res.candidates, chosen: res.chosen, automatic: res.automaticChosen, error: p.error) { how in
                            switch how {
                            case .chosen(let c): await model.recut(id, .chosen(c))
                            case .box(let b, let c): await model.recut(id, .box(b, chosen: c))
                            }
                        }
                    } else if pr.cutoutResult == nil {
                        ContentUnavailableView("Can't adjust this one", systemImage: "exclamationmark.triangle",
                                               description: Text(p.error ?? "The item couldn't be found in the original photo. Retake it."))
                    } else { ProgressView() }
                }
            }
            .navigationTitle("Adjust cut-out").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
        .task {
            guard let pr = model.photo(id)?.processed else { return }
            let u = model.store.url(for: pr.originalFile, id: pr.itemID)
            image = await Task.detached { ImageCodec.thumbnail(at: u, maxPixel: 1600) }.value
        }
    }
}

private extension String { var nilIfEmpty: String? { isEmpty ? nil : self } }

/// Read-only chips (review and item detail).
struct LabelChips: View {
    let label: LabelData
    var body: some View {
        let chips: [String] = [[label.brand, label.subBrand].compactMap { $0 }.joined(separator: " · ").nilIfEmpty, label.fabric?.displayName, label.fit?.displayName, label.size.map { "Size \($0)" },
                               label.mrp.map { "MRP ₹\(Int($0))" }, label.salePrice.map { "Sale ₹\(Int($0))" },
                               label.colour, label.styleCode.map { "Style \($0)" }, label.barcode.map { "Barcode \($0)" }].compactMap { $0 }
        if chips.isEmpty { Text("Nothing read from the label.").font(.footnote).foregroundStyle(.secondary) }
        else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack { ForEach(chips, id: \.self) { Text($0).font(.footnote).padding(.horizontal, 10).padding(.vertical, 6).background(.quaternary, in: Capsule()) } }
            }
        }
    }
}
