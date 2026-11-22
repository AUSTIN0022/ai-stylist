import ImagePlayground
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
    @State private var makeProduct = false
    @Environment(\.supportsImagePlayground) private var supportsImagePlayground
    @Query(sort: \Item.createdAt, order: .reverse) private var items: [Item]

    enum CameraKind: Identifiable {
        case retake(UUID), label(UUID)
        var id: UUID { switch self { case .retake(let i), .label(let i): i } }
    }

    var body: some View {
        NavigationStack {
            Group {
                if model.analysing { AnalysisProgress(model: model) } else {
                    TabView(selection: $selected) {
                        ForEach(model.unresolved) { p in page(p).tag(Optional(p.id)) }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                }
            }
            .background(Color(.systemBackground))
            .navigationTitle(model.analysing ? "Working" : selected.map { "\(model.position($0)) of \(model.photos.count)" } ?? "Review")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { model.discardAll() } } }
        }
        .onAppear { model.logContext = context; if selected == nil { selected = model.unresolved.first?.id } }
        .onChange(of: model.isFinished) { _, done in if done { dismiss() } }   // product photos run from the screen that opened the review
        .onChange(of: model.analysing) { _, on in if !on { selected = model.unresolved.first?.id } }
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
                Button("Save") {
                    resolve(p.id) {
                        model.save(p.id, context: context, makeProduct: makeProduct && supportsImagePlayground)
                    }
                }
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
            if let d = p.duplicate {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Is this the same as \(d.name.isEmpty ? "an item you already have" : d.name)?", systemImage: "square.on.square").font(.subheadline.weight(.semibold))
                    Text(String(format: "Photo match %.2f (lower is closer)", d.distance)).font(.caption2).foregroundStyle(.secondary)
                    HStack {
                        Button("Same, discard this photo", role: .destructive) { model.discardAsDuplicate(p.id) }.buttonStyle(.bordered)
                        Button("Different") { model.keepBoth(p.id) }.buttonStyle(.borderedProminent)
                    }.controlSize(.small)
                }.padding(12).frame(maxWidth: .infinity, alignment: .leading).background(.yellow.opacity(0.15), in: RoundedRectangle(cornerRadius: 10))
            }
            if let note = model.note(p) {
                HStack {
                    Label(note, systemImage: "exclamationmark.triangle").font(.footnote).foregroundStyle(.orange)
                    Spacer()
                    Button("Retake") { model.retake(p.id); camera = .retake(p.id) }.buttonStyle(.bordered).controlSize(.small)
                }
            }
            categoryQuestion(p)
            if model.askColor(p) { colorQuestion(p) } else { colourRow(p) }
            if model.askFit(p) { fitQuestion(p) }
            TagChips(model: model, photo: p)
            labelSection(p)
            if supportsImagePlayground { Toggle("Make a product photo after saving", isOn: $makeProduct) }
            else { Text(productShotUnavailableReason).font(.footnote).foregroundStyle(.secondary) }
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

    /// The colour as swatch and name; tap the name to pick another (the choice wins and is saved with the item).
    private func colourRow(_ p: ReviewModel.Photo) -> some View {
        let names = model.colorNames(p), hexes = p.processed?.hexColors ?? []
        return HStack(spacing: 8) {
            Text("Colour").font(.headline)
            Spacer()
            ForEach(Array(names.enumerated()), id: \.offset) { i, n in
                if hexes.indices.contains(i) { Circle().fill(Color(hex: hexes[i])).frame(width: 22, height: 22).overlay(Circle().stroke(.quaternary)) }
                if i == 0 {
                    Menu {
                        ForEach(ColorName.allCases, id: \.self) { c in
                            Button { model.answerColor(p.id, c) } label: { if c == n { Label(c.displayName, systemImage: "checkmark") } else { Text(c.displayName) } }
                        }
                    } label: { Label(n.displayName, systemImage: "chevron.up.chevron.down").labelStyle(.titleAndIcon) }.buttonStyle(.bordered).controlSize(.small)
                } else { Text(n.displayName).font(.footnote).foregroundStyle(.secondary) }
            }
        }
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

extension UUID: @retroactive Identifiable { public var id: UUID { self } }
