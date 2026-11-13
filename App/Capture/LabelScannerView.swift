import StyleEngine
import SwiftUI
import UIKit
import VisionKit
import WardrobeImaging

/// Label capture: the live text scanner when the device has it, else the plain photo camera with a label box.
/// `onCapture(photo, boxInPhoto, liveLines, barcode)` returns a message to keep the scanner open, nil when accepted.
struct LabelCaptureView: View {
    typealias Capture = (Data, CGRect?, [String], String?) async -> String?
    var onCapture: Capture

    var body: some View {
        if DataScannerViewController.isSupported && DataScannerViewController.isAvailable {
            LabelScannerView(onCapture: onCapture)
        } else {
            CameraView(label: true, singleShot: true, hint: "Fit the label in the box") { shots in
                if let s = shots.first { Task { _ = await onCapture(s.data, s.box, [], nil) } }
            }
        }
    }
}

/// Live-recognised text is highlighted by VisionKit; the target box is the scanner's region of interest.
private struct LabelScannerView: View {
    var onCapture: LabelCaptureView.Capture
    @Environment(\.dismiss) private var dismiss
    @State private var model = ScannerModel()
    @State private var message: String?
    @State private var busy = false

    var body: some View {
        LabelScannerLayout(message: message, canCapture: model.textInBox && !busy, onCancel: { dismiss() },
                           onCapture: { box, size in capture(box: box, size: size) }) { box in
            ScannerRepresentable(model: model, box: box)
        }
    }

    private func capture(box: CGRect, size: CGSize) {
        busy = true; message = nil
        let live = model.lines, code = model.barcode
        Task {
            defer { busy = false }
            guard let image = try? await model.vc?.capturePhoto(), let data = image.jpegData(compressionQuality: 0.9) else {
                message = "Couldn't take the photo, try again"; return
            }
            // The still keeps the view's aspect-fill mapping, so the existing guide -> photo conversion applies.
            let rect = CameraBox.photoRect(forGuide: box, preview: size, photo: image.size)
            if let m = await onCapture(data, rect, live, code) { message = m } else { dismiss() }
        }
    }
}

/// The scanner screen: `background` fills the whole screen; box, hint and controls are drawn over it.
/// Split out so a plain colour can stand in for the camera (DataScanner does not run in the simulator).
struct LabelScannerLayout<Background: View>: View {
    var message: String?
    var canCapture: Bool
    var onCancel: () -> Void
    var onCapture: (CGRect, CGSize) -> Void
    @ViewBuilder var background: (CGRect) -> Background

    // Root cause of "controls under the box": the spacer cell `Color.clear.frame(maxWidth: .infinity)` is greedy
    // vertically too, so the button row took half the free height and centred its buttons in it. It now has maxHeight 0
    // (same fix in CameraView). The full-screen GeometryReader gives box and camera the whole screen; hint and
    // controls are overlays of the outer view, so they sit inside the top and bottom safe area.
    @State private var screen = CGSize.zero

    var body: some View {
        let box = CameraView.labelGuide(in: screen)
        Color.black.ignoresSafeArea()
            .overlay {
                GeometryReader { geo in
                    ZStack {
                        background(CameraView.labelGuide(in: geo.size))
                        RoundedRectangle(cornerRadius: 16)
                            .strokeBorder(.white.opacity(0.85), style: StrokeStyle(lineWidth: 3, dash: [10, 8]))
                            .frame(width: CameraView.labelGuide(in: geo.size).width, height: CameraView.labelGuide(in: geo.size).height)
                            .position(x: CameraView.labelGuide(in: geo.size).midX, y: CameraView.labelGuide(in: geo.size).midY)
                            .accessibilityHidden(true)
                    }
                    .frame(width: geo.size.width, height: geo.size.height)
                    .onAppear { screen = geo.size }
                    .onChange(of: geo.size) { _, new in screen = new }
                }
                .ignoresSafeArea()
            }
            .overlay(alignment: .top) {
                Text(message ?? "Fit the label in the box")
                    .font(.subheadline.weight(.medium)).foregroundStyle(.white)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background((message == nil ? Color.black.opacity(0.55) : Color.red.opacity(0.8)), in: Capsule())
                    .padding(.top, 12)
            }
            .overlay(alignment: .bottom) {
                HStack {
                    Button("Cancel", action: onCancel).frame(maxWidth: .infinity)
                    Button { onCapture(box, screen) } label: {
                        Circle().fill(.white).frame(width: 68, height: 68)
                            .overlay(Circle().stroke(.white.opacity(0.6), lineWidth: 4).frame(width: 80, height: 80))
                    }
                    .disabled(!canCapture).opacity(canCapture ? 1 : 0.4)
                    .accessibilityLabel("Take photo")
                    Color.clear.frame(maxWidth: .infinity, maxHeight: 0)
                }
                .foregroundStyle(.white).padding(.vertical, 16)
            }
    }
}

/// What the scanner currently sees inside the box. Lines are top-to-bottom, left-to-right.
@MainActor @Observable private final class ScannerModel {
    @ObservationIgnored weak var vc: DataScannerViewController?
    private(set) var lines: [String] = []
    private(set) var barcode: String?
    var textInBox: Bool { !lines.isEmpty }

    func update(_ items: [RecognizedItem], box: CGRect) {
        func inBox(_ b: RecognizedItem.Bounds) -> Bool {
            let c = CGPoint(x: (b.topLeft.x + b.bottomRight.x) / 2, y: (b.topLeft.y + b.bottomRight.y) / 2)
            return box.insetBy(dx: -8, dy: -8).contains(c)
        }
        var found: [(CGPoint, String)] = []
        var code: String?
        for case .text(let t) in items where inBox(t.bounds) { found.append((t.bounds.topLeft, t.transcript)) }
        for case .barcode(let b) in items where inBox(b.bounds) { code = code ?? b.payloadStringValue }
        found.sort { abs($0.0.y - $1.0.y) > 8 ? $0.0.y < $1.0.y : $0.0.x < $1.0.x }
        lines = found.map(\.1); barcode = code
    }
}

private struct ScannerRepresentable: UIViewControllerRepresentable {
    let model: ScannerModel
    let box: CGRect

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let vc = DataScannerViewController(recognizedDataTypes: [.text(), .barcode()], qualityLevel: .accurate,
                                           recognizesMultipleItems: true, isHighFrameRateTrackingEnabled: false,
                                           isPinchToZoomEnabled: true, isGuidanceEnabled: false, isHighlightingEnabled: true)
        model.vc = vc
        try? vc.startScanning()
        context.coordinator.stream = Task { @MainActor [weak vc] in
            guard let vc else { return }
            for await items in vc.recognizedItems { model.update(items, box: context.coordinator.box) }
        }
        return vc
    }

    func updateUIViewController(_ vc: DataScannerViewController, context: Context) {
        context.coordinator.box = box
        vc.regionOfInterest = box
    }

    static func dismantleUIViewController(_ vc: DataScannerViewController, coordinator: Coordinator) {
        coordinator.stream?.cancel(); vc.stopScanning()
    }

    func makeCoordinator() -> Coordinator { Coordinator() }
    final class Coordinator { var box = CGRect.zero; var stream: Task<Void, Never>? }
}
