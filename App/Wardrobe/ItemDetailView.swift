import ImagePlayground
import StyleEngine
import SwiftData
import SwiftUI
import WardrobeImaging

struct ItemDetailView: View {
    let item: Item
    @Environment(AppEnvironment.self) private var env
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var confirmDelete = false
    @State private var editing = false
    @State private var rescanning = false
    @State private var rescanMessage: String?
    @State private var review: ReviewModel?
    @State private var labelFullScreen = false
    @Query(sort: \Item.createdAt, order: .reverse) private var allItems: [Item]
    @Environment(\.supportsImagePlayground) private var supportsImagePlayground
    @State private var shot = ProductShotSession()
    @State private var shown: ImageKind?
    @State private var reloads = 0
    @State private var lastReview: ReviewModel?

    private var store: ImageStore { env.store }

    enum ImageKind: String, CaseIterable, Identifiable { case product = "Product", cutout = "Cut-out", photo = "Photo"; var id: String { rawValue } }
    private var hasProduct: Bool { _ = reloads; return ProductShotSession.hasProduct(item, store: store) }
    private var kind: ImageKind { let k = shown ?? (hasProduct ? .product : .cutout); return k == .product && !hasProduct ? .cutout : k }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                FileImage(url: store.url(for: kind == .product ? ImageStore.productName : kind == .photo ? item.originalFile : item.displayFile, id: item.id),
                          fallback: store.url(for: item.displayFile, id: item.id), maxPixel: 1024)
                    .frame(maxWidth: .infinity).aspectRatio(kind == .photo ? 3.0 / 4.0 : 4.0 / 5.0, contentMode: .fit)
                    .background(.white).clipShape(RoundedRectangle(cornerRadius: 16))
                    .overlay { ProductShotOverlay(state: shot.overlay) }
                Picker("Image", selection: Binding(get: { kind }, set: { shown = $0 })) {
                    ForEach(ImageKind.allCases.filter { $0 != .product || hasProduct }) { Text($0.rawValue).tag($0) }
                }.pickerStyle(.segmented)
                if supportsImagePlayground {
                    HStack {
                        Button {
                            Task {
                                shot.context = context
                                if await shot.make(for: item) == .saved { shown = .product }
                            }
                        } label: {
                            if shot.isBusy { ProgressView() } else { Label(hasProduct ? "Make product photo again" : "Make product photo", systemImage: "wand.and.stars") }
                        }.buttonStyle(.bordered).disabled(shot.isBusy)
                        if hasProduct {
                            Button("Remove product photo", role: .destructive) { ProductShotSession.removeProductPhoto(item, store: store); shown = nil }
                                .buttonStyle(.bordered)
                        }
                    }
                    if let m = shot.errorMessage { Text(m).font(.footnote).foregroundStyle(.red) }
                } else {
                    Text(productShotUnavailableReason).font(.footnote).foregroundStyle(.secondary)
                }
                if ProductShotPrompt.hasSleeves(item.tags) {
                    HStack {
                        Text("Sleeve").font(.headline)
                        Spacer()
                        Picker("Sleeve", selection: Binding(get: { item.tags.sleeve }, set: { item.setOverride(\.sleeve, to: $0, context: context) })) {
                            Text("Not set").tag(Sleeve?.none)
                            ForEach(Sleeve.allCases, id: \.self) { Text($0.displayName).tag(Optional($0)) }
                        }.pickerStyle(.menu)
                    }
                }
                Button("Review again", systemImage: "checklist") {
                    let m = ReviewModel.live(env); m.beginExisting([item]); review = m
                }.buttonStyle(.bordered)
                if item.cutoutFailed {
                    Label("Cut-out failed, showing the original photo. Delete and retake it for a clean image.",
                          systemImage: "exclamationmark.triangle").font(.footnote).foregroundStyle(.orange)
                }
                if !item.hexColors.isEmpty {
                    Text("Colours").font(.headline)
                    ForEach(Array(item.hexColors.enumerated()), id: \.offset) { i, hex in
                        HStack(spacing: 12) {
                            Circle().fill(Color(hex: hex)).frame(width: 36, height: 36).overlay(Circle().stroke(.quaternary))
                            VStack(alignment: .leading) {
                                Text("#\(hex)").font(.body.monospaced())
                                if let n = name(at: i) { Text(n).font(.caption).foregroundStyle(.secondary) }
                            }
                            Spacer()
                            if item.colorNames.indices.contains(i) && item.colorNames != [ColorName.multicolor.rawValue] {
                                Menu("Change") {
                                    ForEach(ColorName.allCases, id: \.self) { c in
                                        Button { item.setColour(c, at: i, context: context) } label: {
                                            if item.colorNames[i] == c.rawValue { Label(c.displayName, systemImage: "checkmark") } else { Text(c.displayName) }
                                        }
                                    }
                                }.buttonStyle(.bordered).controlSize(.small)
                            }
                        }
                    }
                    if item.colorNames == [ColorName.multicolor.rawValue] {
                        Text("Multicolour").font(.caption).foregroundStyle(.secondary)
                    }
                }
                if let label = item.label {
                    HStack {
                        Text("Label").font(.headline)
                        Spacer()
                        Button("Edit") { editing = true }.buttonStyle(.bordered).controlSize(.small)
                        Button("Rescan label") { rescanning = true }.buttonStyle(.bordered).controlSize(.small)
                    }
                    LabelChips(label: label)
                    if let m = rescanMessage { Text(m).font(.footnote).foregroundStyle(.red) }
                    if item.labelData != nil, FileManager.default.fileExists(atPath: store.url(for: ImageStore.labelName, id: item.id).path) {
                        Button { labelFullScreen = true } label: {
                            FileImage(url: store.url(for: ImageStore.labelName, id: item.id), maxPixel: 800)
                                .frame(maxHeight: 160).clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                        .buttonStyle(.plain).accessibilityLabel("Label photo, open full screen")
                    }
                }
                if item.label == nil {
                    Button("Scan label", systemImage: "text.viewfinder") { rescanning = true }.buttonStyle(.bordered)
                }
                Button("Delete item", role: .destructive) { confirmDelete = true }
                    .buttonStyle(.bordered).padding(.top, 8)
            }
            .padding(16)
        }
        .productShotSheet(shot)
        .onReceive(NotificationCenter.default.publisher(for: .itemImagesChanged)) { n in if (n.object as? UUID) == item.id { reloads += 1 } }
        .contentMargins(.bottom, 80, for: .scrollContent)   // clear of the floating tab bar: Delete and the label photo stay reachable
        .navigationTitle(item.name.isEmpty ? "Item" : item.name)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $editing) {
            LabelEditor(initial: item.label ?? LabelData(), pastBrands: Item.pastBrands(allItems)) { item.setLabel($0, context: context); editing = false }
                onCancel: { editing = false }
        }
        .fullScreenCover(item: $review, onDismiss: {
            guard let ids = review?.takeProductQueue() ?? lastReview?.takeProductQueue(), !ids.isEmpty else { return }
            Task { await shot.makeQueued(ids, context: context) }
        }) { m in ReviewView(model: m).onAppear { lastReview = m } }
        .fullScreenCover(isPresented: $labelFullScreen) {
            ZStack(alignment: .topTrailing) {
                Color.black.ignoresSafeArea()
                FileImage(url: store.url(for: ImageStore.labelName, id: item.id), maxPixel: 2048).padding(8)
                Button("Close") { labelFullScreen = false }.buttonStyle(.borderedProminent).padding(16)
            }
            .onTapGesture { labelFullScreen = false }
        }
        .fullScreenCover(isPresented: $rescanning) {
            LabelCaptureView { photo, box, live, code in
                let out = await LabelPipeline().run(photo: photo, box: box, liveLines: live, liveBarcode: code, pastBrands: Item.pastBrands(allItems))
                switch out {
                case .read(let d, let jpeg): item.replaceLabel(d, jpeg: jpeg, store: store, context: context); rescanMessage = nil; return nil
                case .blurry: rescanMessage = LabelPipeline.blurryMessage; return LabelPipeline.blurryMessage
                case .unreadable: rescanMessage = "Couldn't read that photo, try again"; return rescanMessage
                }
            }
        }
        .confirmationDialog("Delete this item and its photos?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                dismiss()
                Item.delete(item, in: context, store: store)
            }
        }
    }

    private func name(at i: Int) -> String? {
        guard item.colorNames.indices.contains(i), let c = ColorName(rawValue: item.colorNames[i]) else { return nil }
        return c.displayName
    }
}
