import StyleEngine
import SwiftData
import SwiftUI
import WardrobeImaging

/// Full-screen review pager. Nothing is saved until Save (see ReviewModel).
struct ReviewView: View {
    @Bindable var model: ReviewModel
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var selected: UUID?
    @State private var adjusting: UUID?
    @State private var camera: CameraKind?
    @State private var draft: ReviewModel.LabelDraft?   // shown once the scanner has dismissed
    @State private var labelMessage: String?
    @State private var preparingAdjust = false
    @Query(sort: \Item.createdAt, order: .reverse) private var items: [Item]

    enum CameraKind: Identifiable {
        case retake(UUID), label(UUID)
        var id: UUID { switch self { case .retake(let i), .label(let i): i } }
    }

    var body: some View {
        NavigationStack {
            TabView(selection: $selected) {
                ForEach(model.unresolved) { p in page(p).tag(Optional(p.id)) }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .background(Color(.systemBackground))
            .navigationTitle(selected.map { "\(model.position($0)) of \(model.photos.count)" } ?? "Review")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { model.discardAll() } } }
        }
        .onAppear { model.logContext = context; if selected == nil { selected = model.unresolved.first?.id } }
        .onChange(of: model.isFinished) { _, done in if done { dismiss() } }
        .fullScreenCover(item: $camera, onDismiss: { draft = model.labelDraft }) { kind in
            switch kind {
            case .retake(let id):
                CameraView(singleShot: true) { shots in
                    if let s = shots.first { Task { await model.replace(id, data: s.data, box: s.box) } }
                }
            case .label(let id):
                LabelCaptureView { photo, box, live, code in
                    let m = await model.scanLabel(id, photo: photo, box: box, liveLines: live, liveBarcode: code, pastBrands: Item.pastBrands(items))
                    labelMessage = m
                    return m
                }
            }
        }
        .onChange(of: model.labelDraft?.id) { _, _ in if camera == nil { draft = model.labelDraft } }
        .sheet(item: $adjusting) { id in AdjustSheet(model: model, id: id) }
        .sheet(item: $draft) { d in
            LabelEditor(initial: d.data, pastBrands: Item.pastBrands(items)) { model.confirmLabel($0); draft = nil } onCancel: { model.labelDraft = nil; draft = nil }
        }
    }

    /// Moves to the next unresolved photo, then runs the action.
    private func resolve(_ id: UUID, _ action: () -> Void) {
        let rest = model.unresolved.map(\.id)
        let next = rest.firstIndex(of: id).flatMap { i in rest.indices.contains(i + 1) ? rest[i + 1] : rest.first { $0 != id } }
        action()
        selected = next
    }

    @ViewBuilder private func page(_ p: ReviewModel.Photo) -> some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    switch p.status {
                    case .processing:
                        ProgressView("Cutting out…").frame(maxWidth: .infinity, minHeight: 360)
                    case .failed:
                        ContentUnavailableView("Couldn't read photo", systemImage: "photo.badge.exclamationmark",
                                               description: Text("Retake it or discard it."))
                    default:
                        content(p)
                    }
                }
                .padding(16)
            }
            HStack {
                Button("Retake") { model.retake(p.id); camera = .retake(p.id) }
                Button("Re-tag") { model.retag(p.id) }.disabled(p.tagState == .running)
                // A saved item is never deleted from here: Skip leaves it as it was.
                Button(p.existingID == nil ? "Discard" : "Skip", role: p.existingID == nil ? .destructive : nil) { resolve(p.id) { model.discard(p.id) } }
                Spacer()
                Button("Save") { resolve(p.id) { model.save(p.id, context: context) } }
                    .buttonStyle(.borderedProminent).disabled(p.processed == nil)
            }
            .buttonStyle(.bordered).padding(16)
        }
    }

    @ViewBuilder private func content(_ p: ReviewModel.Photo) -> some View {
        if let pr = p.processed {
            if pr.cutoutResult?.needsChoice == true, p.existingID == nil {
                Text("Tap the item").font(.headline)
                CutoutPicker(model: model, photo: p)
            } else {
                CutoutPreview(store: model.store, processed: pr)
                if p.existingID != nil || !(pr.cutoutResult?.candidates.isEmpty ?? true) {
                    Button { Task { preparingAdjust = true; await model.prepareAdjust(p.id); preparingAdjust = false; adjusting = p.id } } label: {
                        if preparingAdjust { ProgressView() } else { Text("Adjust cut-out") }
                    }.buttonStyle(.bordered).disabled(preparingAdjust)
                }
            }
            if let note = model.note(p) {
                HStack {
                    Label(note, systemImage: "exclamationmark.triangle").font(.footnote).foregroundStyle(.orange)
                    Spacer()
                    Button("Retake") { model.retake(p.id); camera = .retake(p.id) }.buttonStyle(.bordered).controlSize(.small)
                }
            }
            categoryQuestion(p)
            if model.askColor(p) { colorQuestion(p) }
            if model.askFit(p) { fitQuestion(p) }
            TagChips(model: model, photo: p)
            labelSection(p)
        }
    }

    /// The AI's answer is preselected as one chip with up to two alternatives; "Something else" (or no answer) shows the full lists.
    /// Any change is a user correction; the AI's answer stays in aiRaw.
    private func categoryQuestion(_ p: ReviewModel.Photo) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("What is it?").font(.headline)
            if let ai = p.ai, let s = model.suggestion(p) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        chip(s.title, on: model.effectiveSubcategory(p) == ai.subcategory && model.effectiveCategory(p) == ai.category) { model.acceptSuggestion(p.id) }
                        ForEach(s.alternatives, id: \.self) { alt in
                            chip(alt.displayName, on: model.effectiveSubcategory(p) == alt && model.effectiveCategory(p) == ai.category) { model.answerSubcategory(p.id, alt) }
                        }
                        chip("Something else", on: false) { model.showAllChoices(p.id) }
                    }
                }
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(Category.allCases, id: \.self) { c in chip(c.displayName, on: model.effectiveCategory(p) == c) { model.answerCategory(p.id, c) } }
                    }
                }
                if let c = model.effectiveCategory(p) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            ForEach(subcategories(for: c), id: \.self) { s in chip(s.displayName, on: model.effectiveSubcategory(p) == s) { model.answerSubcategory(p.id, s) } }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder private func chip(_ title: String, on: Bool, _ action: @escaping () -> Void) -> some View {
        if on { Button(title, action: action).buttonStyle(.borderedProminent) } else { Button(title, action: action).buttonStyle(.bordered) }
    }

    private func colorQuestion(_ p: ReviewModel.Photo) -> some View {
        let choices = model.colorChoices(p)
        return VStack(alignment: .leading, spacing: 8) {
            Text("Is this \(choices.first?.displayName.lowercased() ?? "colour")?").font(.headline)
            HStack {
                Button("Yes") { model.skipColor(p.id) }
                ForEach(choices.dropFirst(), id: \.self) { c in Button(c.displayName) { model.answerColor(p.id, c) } }
                Menu("Other") {
                    ForEach(ColorName.allCases.filter { $0 != .multicolor }, id: \.self) { c in
                        Button(c.displayName) { model.answerColor(p.id, c) }
                    }
                }
            }.buttonStyle(.bordered)
        }
    }

    private func fitQuestion(_ p: ReviewModel.Photo) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("How does it fit?").font(.headline)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack {
                    ForEach(Fit.allCases, id: \.self) { f in Button(f.displayName) { model.answerFit(p.id, f) } }
                    Button("Skip") { model.skipFit(p.id) }
                }.buttonStyle(.bordered)
            }
        }
    }

    private func labelSection(_ p: ReviewModel.Photo) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let l = p.label {
                Text("Label").font(.headline)
                LabelChips(label: l)
            }
            Button(p.label == nil ? "Scan label" : "Scan label again", systemImage: "text.viewfinder") { camera = .label(p.id) }
                .buttonStyle(.bordered)
            if let m = labelMessage { Text(m).font(.footnote).foregroundStyle(.red) }
        }
    }
}

/// Cut-out on white with an original toggle.
private struct CutoutPreview: View {
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
private struct CutoutPicker: View {
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

private struct AdjustSheet: View {
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

extension UUID: @retroactive Identifiable { public var id: UUID { self } }

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
