import StyleEngine
import SwiftData
import SwiftUI
import WardrobeImaging

struct ItemDetailView: View {
    let item: Item
    let store: ImageStore
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var confirmDelete = false
    @State private var editing = false
    @State private var rescanning = false
    @State private var rescanMessage: String?
    @State private var review: ReviewModel?
    @State private var labelFullScreen = false
    @Query(sort: \Item.createdAt, order: .reverse) private var allItems: [Item]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                FileImage(url: store.url(for: item.displayFile, id: item.id), maxPixel: 1024)
                    .frame(maxWidth: .infinity).aspectRatio(1, contentMode: .fit)
                    .background(.white).clipShape(RoundedRectangle(cornerRadius: 16))
                Button("Review again", systemImage: "checklist") {
                    let m = ReviewModel.live(); m.beginExisting([item]); review = m
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
                        }
                        .accessibilityElement(children: .combine)
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
        .contentMargins(.bottom, 80, for: .scrollContent)   // clear of the floating tab bar: Delete and the label photo stay reachable
        .navigationTitle(item.name.isEmpty ? "Item" : item.name)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $editing) {
            LabelEditor(initial: item.label ?? LabelData(), pastBrands: Item.pastBrands(allItems)) { item.setLabel($0, context: context); editing = false }
                onCancel: { editing = false }
        }
        .fullScreenCover(item: $review) { ReviewView(model: $0) }
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

extension Color {
    init(hex: String) {
        let v = UInt32(hex, radix: 16) ?? 0
        self.init(.sRGB, red: Double((v >> 16) & 255) / 255, green: Double((v >> 8) & 255) / 255, blue: Double(v & 255) / 255)
    }
}
