import PhotosUI
import StyleEngine
import SwiftData
import SwiftUI
import WardrobeImaging

/// The one way to add clothes: set `trigger` from a "+" button and this asks Camera or Photo library, runs the review and
/// queues product photos afterwards. With `preset` (a category page) every photo starts in that category and the AI only cross-checks it.
struct AddItemsFlow: ViewModifier {
    @Binding var trigger: Bool
    var preset: StyleEngine.Category?
    @Environment(\.modelContext) private var context
    @Environment(AppEnvironment.self) private var env
    @State private var showCamera = false
    @State private var showPicker = false
    @State private var picked: [PhotosPickerItem] = []
    @State private var review: ReviewModel?
    @State private var fromCamera: ReviewModel?      // opened once the camera has dismissed
    @State private var lastReview: ReviewModel?      // its product-photo queue runs once the review has gone
    @State private var shot = ProductShotSession()

    func body(content: Content) -> some View {
        content
            .confirmationDialog(preset.map { "Add to \($0.displayName)" } ?? "Add items", isPresented: $trigger, titleVisibility: .visible) {
                Button("Take photos") { showCamera = true }
                Button("Photo library") { showPicker = true }
            }
            .photosPicker(isPresented: $showPicker, selection: $picked, maxSelectionCount: 20, matching: .images)
            .onChange(of: picked) { _, new in
                guard !new.isEmpty else { return }
                let chosen = new
                picked = []
                let m = ReviewModel.live(env, presetCategory: preset)
                m.begin(count: chosen.count) { i in try? await chosen[i].loadTransferable(type: Data.self) }
                review = m
            }
            .fullScreenCover(isPresented: $showCamera, onDismiss: { review = fromCamera; fromCamera = nil }) {
                CameraView { shots in
                    let m = ReviewModel.live(env, presetCategory: preset)
                    m.begin(count: shots.count, box: { shots[$0].box }) { shots[$0].data }
                    fromCamera = m
                }
            }
            .fullScreenCover(item: $review, onDismiss: {
                guard let ids = lastReview?.takeProductQueue(), !ids.isEmpty else { return }
                Task { await shot.makeQueued(ids, context: context) }
            }) { m in ReviewView(model: m).onAppear { lastReview = m } }
            .productShotSheet(shot)
    }
}

extension View {
    func addItemsFlow(trigger: Binding<Bool>, preset: StyleEngine.Category? = nil) -> some View { modifier(AddItemsFlow(trigger: trigger, preset: preset)) }
}
