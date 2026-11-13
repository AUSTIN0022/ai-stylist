import SwiftData
import SwiftUI
import WardrobeImaging

@main
struct AIStylistApp: App {
    private let container: ModelContainer

    init() {
        let c = try! ModelContainer(for: Schema(Item.allModels))
        container = c
        // One background tagging queue for the whole app; items left in `tagging` resume at launch.
        let queue = TaggingQueue(container: c, store: .standard, tagger: FoundationModelsTagger())
        Task { @MainActor in AppServices.tagging = queue; await queue.start() }
    }

    var body: some Scene {
        WindowGroup {
            #if DEBUG
            // Layout proofs for the simulator: `-layoutDebug scanner|camera` (DataScanner needs a real device).
            switch UserDefaults.standard.string(forKey: "layoutDebug") {
            case "scanner": LabelScannerLayout(message: nil, canCapture: true, onCancel: {}, onCapture: { _, _ in }) { _ in Color.teal }
            case "camera": CameraView(label: true, singleShot: true, hint: "Fit the label in the box") { _ in }
            case "adjust": NavigationStack { AdjustCanvasDebug() }
            default: ContentView()
            }
            #else
            ContentView()
            #endif
        }
        .modelContainer(container)
    }
}
