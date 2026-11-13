import AVFoundation
import SwiftUI
import UIKit
import WardrobeImaging

/// One photo plus the camera guide in photo coordinates (normalised, top-left origin); nil without a box.
struct CapturedShot { let data: Data; let box: CGRect? }

/// In-app camera: framing guide, a shutter that stays open for the next shot, and a strip of what was taken.
/// `label` swaps the guide for the small label box (fallback when the live scanner is unavailable);
/// `singleShot` returns after one photo (retake, label).
struct CameraView: View {
    var showBox = true
    var label = false
    var singleShot = false
    var hint = "Fit one item inside the box · plain background · good light"
    var onDone: ([CapturedShot]) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var camera = CameraModel()

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if camera.denied {
                ContentUnavailableView("Camera is off", systemImage: "camera.fill",
                                       description: Text("Allow camera access in Settings to take photos."))
                    .foregroundStyle(.white)
            } else {
                GeometryReader { geo in
                    ZStack {
                        CameraPreview(session: camera.session)
                        if showBox {
                            let g = guide(in: geo.size)
                            RoundedRectangle(cornerRadius: 28)
                                .strokeBorder(.white.opacity(0.85), style: StrokeStyle(lineWidth: 3, dash: [10, 8]))
                                .frame(width: g.width, height: g.height)
                                .position(x: g.midX, y: g.midY)
                                .accessibilityHidden(true)
                        }
                    }
                    .onAppear { camera.setGuide(showBox ? guide(in: geo.size) : nil, preview: geo.size) }
                    .onChange(of: geo.size) { _, new in camera.setGuide(showBox ? guide(in: new) : nil, preview: new) }
                }
                .ignoresSafeArea()
            }
            VStack {
                Text(hint)
                    .font(.subheadline.weight(.medium)).foregroundStyle(.white)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(.black.opacity(0.55), in: Capsule())
                    .padding(.top, 12)
                Spacer()
                if !camera.thumbnails.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(Array(camera.thumbnails.enumerated()), id: \.offset) { _, t in
                                Image(uiImage: t).resizable().scaledToFill()
                                    .frame(width: 52, height: 52).clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                        }.padding(.horizontal, 16)
                    }.frame(height: 56)
                }
                HStack {
                    Button("Cancel") { dismiss() }.frame(maxWidth: .infinity)
                    Button { camera.capture() } label: {
                        Circle().fill(.white).frame(width: 68, height: 68)
                            .overlay(Circle().stroke(.white.opacity(0.6), lineWidth: 4).frame(width: 80, height: 80))
                    }
                    .disabled(camera.denied)
                    .accessibilityLabel("Take photo")
                    if singleShot { Color.clear.frame(maxWidth: .infinity, maxHeight: 0) } else {
                        Button("Done (\(camera.shots.count))") { onDone(camera.shots); dismiss() }
                            .disabled(camera.shots.isEmpty).fontWeight(.semibold).frame(maxWidth: .infinity)
                    }
                }
                .foregroundStyle(.white).padding(.vertical, 16)
            }
        }
        .onChange(of: camera.shots.count) { _, n in if singleShot, n == 1 { onDone(camera.shots); dismiss() } }
        .task { await camera.start() }
        .onDisappear { camera.stop() }
    }

    private func guide(in size: CGSize) -> CGRect { label ? Self.labelGuide(in: size) : Self.guide(in: size) }

    /// The label box: 80% of the width, height 1:2.5 of the width, a little above centre.
    static func labelGuide(in size: CGSize) -> CGRect {
        let w = size.width * 0.8, h = w / 2.5
        return CGRect(x: (size.width - w) / 2, y: size.height * 0.42 - h / 2, width: w, height: h)
    }

    /// About 85% of the screen width at 3:4, a little above centre (clamped so it never runs under the controls).
    static func guide(in size: CGSize) -> CGRect {
        var w = size.width * 0.85, h = w * 4 / 3
        if h > size.height * 0.7 { h = size.height * 0.7; w = h * 3 / 4 }
        return CGRect(x: (size.width - w) / 2, y: size.height * 0.47 - h / 2, width: w, height: h)
    }
}

@MainActor @Observable final class CameraModel: NSObject, AVCapturePhotoCaptureDelegate {
    @ObservationIgnored nonisolated(unsafe) let session = AVCaptureSession()
    @ObservationIgnored nonisolated(unsafe) private let output = AVCapturePhotoOutput()
    private let queue = DispatchQueue(label: "camera.session")
    private(set) var shots: [CapturedShot] = []
    @ObservationIgnored private var guide: CGRect?
    @ObservationIgnored private var previewSize = CGSize.zero
    private(set) var thumbnails: [UIImage] = []
    private(set) var denied = false

    func start() async {
        guard await AVCaptureDevice.requestAccess(for: .video) else { denied = true; return }
        nonisolated(unsafe) let session = session, output = output
        queue.async {
            guard session.inputs.isEmpty,
                  let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
                  let input = try? AVCaptureDeviceInput(device: device) else { session.startRunning(); return }
            session.beginConfiguration()
            session.sessionPreset = .photo
            if session.canAddInput(input) { session.addInput(input) }
            if session.canAddOutput(output) { session.addOutput(output) }
            session.commitConfiguration()
            session.startRunning()
        }
    }

    func setGuide(_ g: CGRect?, preview: CGSize) { guide = g; previewSize = preview }

    func stop() {
        nonisolated(unsafe) let session = session
        queue.async { session.stopRunning() }
    }

    func capture() {
        if let c = output.connection(with: .video), c.isVideoRotationAngleSupported(90) { c.videoRotationAngle = 90 }  // portrait
        output.capturePhoto(with: AVCapturePhotoSettings(), delegate: self)
    }

    nonisolated func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        guard error == nil, let data = photo.fileDataRepresentation() else { return }
        Task { @MainActor in
            let cg = ImageCodec.decode(data, maxPixel: 160)   // upright, so its size gives the photo's aspect
            var box: CGRect?
            if let g = guide, let cg, previewSize.width > 0 {
                box = CameraBox.photoRect(forGuide: g, preview: previewSize, photo: CGSize(width: cg.width, height: cg.height))
            }
            shots.append(CapturedShot(data: data, box: box))
            if let cg { thumbnails.append(UIImage(cgImage: cg)) }
        }
    }
}

private struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    func makeUIView(context: Context) -> PreviewView {
        let v = PreviewView(); v.previewLayer.session = session; v.previewLayer.videoGravity = .resizeAspectFill; return v
    }
    func updateUIView(_ uiView: PreviewView, context: Context) {}
    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }
}
