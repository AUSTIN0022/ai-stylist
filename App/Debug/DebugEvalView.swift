import SwiftUI
import WardrobeImaging

/// Sprint 0 spike screens. Throwaway; reach it from a debug menu (not wired into ContentView).
/// Has its own NavigationStack so it can be presented as a sheet or full-screen cover.
public struct DebugEvalView: View {
    @State private var model = SpikeEvalModel()

    public init() {}

    public var body: some View {
        NavigationStack {
            List {
                Section("Model") { Text(model.availability) }
                if !model.loadProblems.isEmpty {
                    Section("Problems") { ForEach(model.loadProblems, id: \.self) { Text($0).foregroundStyle(.red) } }
                }
                Section {
                    Picker("Image long side", selection: $model.longSide) {
                        Text("512").tag(CGFloat(512)); Text("768").tag(CGFloat(768)); Text("1024").tag(CGFloat(1024))
                    }.pickerStyle(.segmented)
                    Button(model.running ? "Running \(model.progress)" : "Run eval (\(model.photos.count) photos)") {
                        Task { await model.run() }
                    }.disabled(model.running || model.photos.isEmpty)
                    NavigationLink("Cut-outs: original vs white") { DebugCutoutView(photos: model.photos) }
                }
                if !model.summary.isEmpty {
                    Section("Summary") {
                        Text(model.summary).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                        ShareLink(item: model.summary)
                    }
                }
                Section("Rows") {
                    ForEach(model.rows) { r in
                        VStack(alignment: .leading) {
                            Text(r.id).font(.headline)
                            Text(SpikeTaxonomy.scoredFields.map { f in
                                "\(f)=\(r.got[f].map(String.init(describing:)) ?? "-")"
                            }.joined(separator: " ")).font(.caption)
                            Text(r.error ?? String(format: "cut %.1fs, tag %.1fs", r.cutoutSeconds ?? 0, r.tagSeconds.reduce(0, +)))
                                .font(.caption2).foregroundStyle(r.error == nil ? Color.secondary : Color.red)
                        }
                    }
                }
            }
            .navigationTitle("Sprint 0 eval")
            .task { model.load() }
        }
    }
}

struct DebugCutoutView: View {
    let photos: [SpikePhoto]
    @State private var cutouts: [String: UIImage] = [:]
    @State private var failed: Set<String> = []

    var body: some View {
        List(photos) { p in
            VStack(alignment: .leading) {
                Text(p.id).font(.caption)
                HStack {
                    AsyncPhoto(url: p.url).frame(maxWidth: .infinity).frame(height: 180)
                    ZStack {
                        Color.white
                        if let c = cutouts[p.id] { Image(uiImage: c).resizable().scaledToFit() }
                        else if failed.contains(p.id) { Text("cut-out failed").foregroundStyle(.red).font(.caption) }
                        else { ProgressView() }
                    }.frame(maxWidth: .infinity).frame(height: 180).border(.gray.opacity(0.4))
                }
            }
            .task { await makeCutout(p) }
        }
        .navigationTitle("Cut-outs")
    }

    private func makeCutout(_ p: SpikePhoto) async {
        guard cutouts[p.id] == nil,
              let ui = UIImage(contentsOfFile: p.url.path),
              let cg = SpikeImage.upright(ui, longSide: 1600),
              let cut = try? await spikeCutout(cg),
              let white = SpikeImage.onWhite(cut, longSide: 600) else { failed.insert(p.id); return }
        cutouts[p.id] = UIImage(cgImage: white)
    }
}

private struct AsyncPhoto: View {
    let url: URL
    @State private var image: UIImage?
    var body: some View {
        Group {
            if let image { Image(uiImage: image).resizable().scaledToFit() } else { ProgressView() }
        }.task {
            if let ui = UIImage(contentsOfFile: url.path), let cg = SpikeImage.upright(ui, longSide: 600) { image = UIImage(cgImage: cg) }
        }
    }
}

#if DEBUG
/// `-layoutDebug adjust`: the Adjust canvas on a synthetic photo (a jacket, two shoes), no model or files.
struct AdjustCanvasDebug: View {
    @State private var error: String?
    private let image: CGImage = {
        let ctx = CGContext(data: nil, width: 600, height: 800, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(red: 0.93, green: 0.92, blue: 0.9, alpha: 1); ctx.fill(CGRect(x: 0, y: 0, width: 600, height: 800))
        ctx.setFillColor(red: 0.7, green: 0.32, blue: 0.17, alpha: 1); ctx.fill(CGRect(x: 120, y: 330, width: 360, height: 400))
        ctx.setFillColor(red: 0.1, green: 0.1, blue: 0.45, alpha: 1)
        ctx.fill(CGRect(x: 90, y: 60, width: 170, height: 90)); ctx.fill(CGRect(x: 340, y: 60, width: 170, height: 90))
        return ctx.makeImage()!
    }()
    private let candidates = [
        CutoutCandidate(index: 0, bounds: CGRect(x: 0.2, y: 0.087, width: 0.6, height: 0.5), areaShare: 0.3, score: 1),
        CutoutCandidate(index: 1, bounds: CGRect(x: 0.15, y: 0.81, width: 0.28, height: 0.11), areaShare: 0.03, score: 0.5),
        CutoutCandidate(index: 2, bounds: CGRect(x: 0.57, y: 0.81, width: 0.28, height: 0.11), areaShare: 0.03, score: 0.5)]
    var body: some View {
        AdjustCanvas(image: image, candidates: candidates, chosen: [0], automatic: [0], error: error) { _ in
            error = "No item inside the box. Move or resize it."; return false
        }
        .navigationTitle("Adjust cut-out").navigationBarTitleDisplayMode(.inline)
    }
}
#endif
