import SwiftUI
import WardrobeImaging

/// Adjust cut-out: the original with zoom (pinch, double-tap), pan, candidate outlines and an optional draggable box.
/// Everything is drawn in view space from `PhotoViewport`, so outlines and the box follow zoom and pan.
/// Pure maths lives in the package (`PhotoViewport`, `SelectionBox`); this view only wires gestures.
struct AdjustCanvas: View {
    enum Apply { case chosen([Int]), box(CGRect, chosen: [Int]?) }

    let image: CGImage
    let candidates: [CutoutCandidate]
    let chosen: [Int]
    let automatic: [Int]
    let error: String?
    /// Runs the re-cut; true = done (the sheet closes), false = stay open (the error is shown).
    let apply: (Apply) async -> Bool

    @State private var picked: Set<Int> = []
    @State private var pickTouched = false
    @State private var boxOn = false
    @State private var box = SelectionBox(CGRect(x: 0.1, y: 0.1, width: 0.8, height: 0.8))
    @State private var scale: CGFloat = 1
    @State private var pan: CGSize = .zero
    @State private var scaleStart: CGFloat = 1
    @State private var drag: DragKind?
    @State private var dragStart = (pan: CGSize.zero, box: SelectionBox(CGRect(x: 0, y: 0, width: 1, height: 1)))
    @State private var lastTap: (time: Date, at: CGPoint)?
    @State private var working = false
    @Environment(\.dismiss) private var dismiss

    enum DragKind { case corner(SelectionBox.Corner), centre, pan }
    private let handle: CGFloat = 44

    var body: some View {
        VStack(spacing: 10) {
            Text(boxOn ? "Drag the corners or the middle. Pinch to zoom." : "Tap every part of the item, such as both shoes. Pinch to zoom.")
                .font(.subheadline).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
            if let error { Label(error, systemImage: "exclamationmark.triangle").font(.footnote).foregroundStyle(.orange).frame(maxWidth: .infinity, alignment: .leading) }
            canvas
            HStack {
                Toggle("Draw box", isOn: $boxOn).toggleStyle(.button).buttonStyle(.bordered)
                    .onChange(of: boxOn) { _, on in if on { box = SelectionBox(currentBounds()) } ; pickTouched = false }
                Button("Reset") { reset() }.buttonStyle(.bordered)
                Spacer()
                Button {
                    Task {
                        working = true
                        let ok = await apply(boxOn ? .box(box.rect, chosen: pickTouched ? picked.sorted() : nil) : .chosen(picked.sorted()))
                        working = false
                        if ok { dismiss() }
                    }
                } label: { if working { ProgressView() } else { Text("Apply") } }
                .buttonStyle(.borderedProminent).disabled(working || (!boxOn && picked.isEmpty))
            }
        }
        .padding(16)
        .onAppear { picked = Set(chosen) }
    }

    private var canvas: some View {
        GeometryReader { geo in
            let vp = viewport(geo.size)
            ZStack {
                ZStack {
                    Image(decorative: image, scale: 1).resizable()
                        .frame(width: vp.fit.width, height: vp.fit.height).position(x: vp.fit.midX, y: vp.fit.midY)
                }
                .frame(width: geo.size.width, height: geo.size.height)
                .scaleEffect(vp.scale).offset(vp.pan)
                overlay(vp)
            }
            .frame(width: geo.size.width, height: geo.size.height).clipped().contentShape(Rectangle())
            .background(Color(.secondarySystemBackground))
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { v in dragChanged(v, geo.size) }
                .onEnded { v in dragEnded(v, geo.size) })
            .simultaneousGesture(MagnifyGesture()
                .onChanged { v in setScale(scaleStart * v.magnification, geo.size) }
                .onEnded { _ in scaleStart = scale })
        }
        .frame(minHeight: 300)
        .accessibilityLabel("Original photo. Tap the item.")
    }

    private func overlay(_ vp: PhotoViewport) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(candidates, id: \.index) { c in
                let on = picked.contains(c.index)
                let r = viewRect(c.bounds, vp)
                Rectangle().stroke(on ? Color.green : Color.yellow.opacity(boxOn ? 0.5 : 1), lineWidth: on ? 3 : 1.5)
                    .frame(width: r.width, height: r.height).offset(x: r.minX, y: r.minY)
            }
            if boxOn {
                let r = viewRect(box.rect, vp)
                Rectangle().stroke(Color.white, lineWidth: 2).background(Color.white.opacity(0.08))
                    .overlay(Rectangle().stroke(Color.accentColor, lineWidth: 1))
                    .frame(width: r.width, height: r.height).offset(x: r.minX, y: r.minY)
                Circle().fill(Color.accentColor).frame(width: 14, height: 14).position(x: r.midX, y: r.midY).offset(x: 0, y: 0)
                ForEach(SelectionBox.Corner.allCases, id: \.self) { c in
                    let p = vp.viewPoint(forPhoto: box.point(c))
                    Circle().fill(Color.white).overlay(Circle().stroke(Color.accentColor, lineWidth: 3)).frame(width: 18, height: 18)
                        .frame(width: handle, height: handle).position(p)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .allowsHitTesting(false)
    }

    // MARK: geometry
    private func viewport(_ size: CGSize) -> PhotoViewport {
        let a = CGFloat(image.width) / CGFloat(image.height)
        let w = min(size.width, size.height * a), h = w / a
        var v = PhotoViewport(container: size, fit: CGRect(x: (size.width - w) / 2, y: (size.height - h) / 2, width: w, height: h))
        v.setScale(scale); v.setPan(pan)
        return v
    }
    private func viewRect(_ r: CGRect, _ vp: PhotoViewport) -> CGRect {
        let a = vp.viewPoint(forPhoto: r.origin), b = vp.viewPoint(forPhoto: CGPoint(x: r.maxX, y: r.maxY))
        return CGRect(x: a.x, y: a.y, width: b.x - a.x, height: b.y - a.y)
    }
    private func setScale(_ s: CGFloat, _ size: CGSize) {
        var v = viewport(size); v.setScale(s); scale = v.scale; pan = v.pan
    }
    private func currentBounds() -> CGRect {
        let rs = candidates.filter { picked.contains($0.index) }.map(\.bounds)
        return rs.dropFirst().reduce(rs.first ?? CGRect(x: 0.1, y: 0.1, width: 0.8, height: 0.8)) { $0.union($1) }
    }
    private func reset() {
        scale = 1; scaleStart = 1; pan = .zero; boxOn = false; pickTouched = false; picked = Set(automatic)
    }

    // MARK: gestures
    private func hitTest(_ p: CGPoint, _ vp: PhotoViewport) -> DragKind {
        guard boxOn else { return .pan }
        for c in SelectionBox.Corner.allCases {
            let q = vp.viewPoint(forPhoto: box.point(c))
            if abs(q.x - p.x) <= handle / 2, abs(q.y - p.y) <= handle / 2 { return .corner(c) }
        }
        return viewRect(box.rect, vp).contains(p) ? .centre : .pan
    }

    private func dragChanged(_ v: DragGesture.Value, _ size: CGSize) {
        var vp = viewport(size)
        if drag == nil { drag = hitTest(v.startLocation, vp); dragStart = (pan, box) }
        let s = vp.photoPoint(forView: v.startLocation), e = vp.photoPoint(forView: v.location)
        switch drag {
        case .corner(let c):
            box = dragStart.box
            let p0 = box.point(c)
            box.dragCorner(c, to: CGPoint(x: p0.x + e.x - s.x, y: p0.y + e.y - s.y))
        case .centre:
            box = dragStart.box; box.dragCentre(by: CGSize(width: e.x - s.x, height: e.y - s.y))
        default:
            vp.setPan(CGSize(width: dragStart.pan.width + v.translation.width, height: dragStart.pan.height + v.translation.height))
            pan = vp.pan
        }
    }

    private func dragEnded(_ v: DragGesture.Value, _ size: CGSize) {
        defer { drag = nil }
        guard hypot(v.translation.width, v.translation.height) < 6 else { return }
        let now = Date()
        if let t = lastTap, now.timeIntervalSince(t.time) < 0.3, hypot(t.at.x - v.location.x, t.at.y - v.location.y) < 30 {
            lastTap = nil
            setScale(scale > 1.01 ? 1 : 2.5, size); scaleStart = scale
            return
        }
        lastTap = (now, v.location)
        tap(viewport(size).photoPoint(forView: v.location))
    }

    /// Smallest outlined part under the finger; with the box on, only parts centred inside the box.
    private func tap(_ pt: CGPoint) {
        let eligible = candidates.filter { c in
            c.bounds.contains(pt) && (!boxOn || box.rect.contains(CGPoint(x: c.bounds.midX, y: c.bounds.midY)))
        }
        guard let c = eligible.min(by: { $0.areaShare < $1.areaShare }) else { return }
        if picked.contains(c.index) { picked.remove(c.index) } else { picked.insert(c.index) }
        pickTouched = true
    }
}
