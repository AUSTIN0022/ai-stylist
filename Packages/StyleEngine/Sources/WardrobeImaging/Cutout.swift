import CoreGraphics
import Vision

public struct CutoutResult: Sendable {
    /// Transparent, cropped to the garment with a small margin.
    public let cutout: CGImage
    /// Subject mask (at most 256 px) for the quality check.
    public let mask: Mask
    /// Every Vision instance, scored (empty for fakes).
    public let candidates: [CutoutCandidate]
    /// Instance indices in the cut-out.
    public let chosen: [Int]
    /// The runner-up scored within 15% of the winner and is not a twin: ask the user to tap.
    public let needsChoice: Bool
    /// Source image + instance masks from the first run, so a re-cut never calls Vision again.
    let session: CutoutSession?

    public init(cutout: CGImage, mask: Mask, candidates: [CutoutCandidate] = [], chosen: [Int] = [], needsChoice: Bool = false) {
        self.init(cutout: cutout, mask: mask, candidates: candidates, chosen: chosen, needsChoice: needsChoice, session: nil)
    }
    init(cutout: CGImage, mask: Mask, candidates: [CutoutCandidate], chosen: [Int], needsChoice: Bool, session: CutoutSession?) {
        self.cutout = cutout; self.mask = mask; self.candidates = candidates; self.chosen = chosen
        self.needsChoice = needsChoice; self.session = session
    }

    /// Re-cut with exactly these instances (no Vision call). Throws `noSubject` for a fake result or bad indices.
    public func recut(chosen: [Int]) throws -> CutoutResult {
        guard let session else { throw CutoutError.noSubject }
        return try session.build(chosen: Array(Set(chosen)).sorted(), candidates: candidates, needsChoice: false, clipToBox: false)
    }
    /// Re-cut with the instance under a tap (normalised photo coordinates, top-left origin), else the nearest.
    public func recut(tap: CGPoint) throws -> CutoutResult {
        guard let session else { throw CutoutError.noSubject }
        return try session.build(chosen: SubjectSelector.select(session.instances, tap: tap), candidates: candidates, needsChoice: false, clipToBox: false)
    }
    /// The automatic choice again (what Reset returns to). Empty for a fake result.
    public var automaticChosen: [Int] { session.map { SubjectSelector.select($0.instances, box: $0.box).chosen } ?? [] }

    /// Re-cut inside a box (normalised, top-left origin), no Vision call: instances centred outside are dropped, the best
    /// is chosen with the usual scoring (or `chosen` when the user ticked parts), the mask is clipped to the box + 10%.
    /// Throws `noItemInBox` when no instance centre is inside, `noSubject` for a fake result.
    public func recut(box: CGRect, chosen picks: [Int]? = nil) throws -> CutoutResult {
        guard let session else { throw CutoutError.noSubject }
        let s = SubjectSelector.select(session.instances, box: box)
        let inside = Set(s.candidates.filter { box.contains(CGPoint(x: $0.bounds.midX, y: $0.bounds.midY)) }.map(\.index))
        let chosen = picks.map { $0.filter(inside.contains) } ?? s.chosen
        if s.noClearItem || chosen.isEmpty { throw CutoutError.noItemInBox }
        return try session.build(chosen: Array(Set(chosen)).sorted(), candidates: candidates, needsChoice: false, clipBox: box)
    }
}

public enum CutoutError: Error { case noSubject, renderFailed, noItemInBox }

/// Seam so pipeline tests run on the Mac with a fake.
public protocol CutoutProviding: Sendable {
    /// `box`: the camera guide, normalised to the photo, top-left origin (nil for library photos).
    func cutout(from image: CGImage, box: CGRect?) async throws -> CutoutResult
}
public extension CutoutProviding {
    func cutout(from image: CGImage) async throws -> CutoutResult { try await cutout(from: image, box: nil) }
}

/// Everything needed to cut out any choice of instances: pure, no Vision.
struct CutoutSession: Sendable {
    let image: CGImage
    let instances: [Mask]
    let box: CGRect?

    func initial() throws -> CutoutResult {
        let s = SubjectSelector.select(instances, box: box)
        if s.noClearItem { throw box == nil ? CutoutError.noSubject : CutoutError.noItemInBox }
        return try build(chosen: s.chosen, candidates: s.candidates, needsChoice: s.needsChoice)
    }

    /// `clipToBox: false` for the user's own choice (Adjust, tap): a part outside the camera box is exactly what they may want.
    func build(chosen: [Int], candidates: [CutoutCandidate], needsChoice: Bool, clipToBox: Bool = true, clipBox: CGRect? = nil) throws -> CutoutResult {
        guard !chosen.isEmpty, chosen.allSatisfy(instances.indices.contains), var merged = Mask.union(chosen.map { instances[$0] }) else { throw CutoutError.noSubject }
        if clipToBox || clipBox != nil, let box = clipBox ?? box {   // box grown 10% of its size per side
            merged = merged.clipped(to: CGRect(x: box.minX - 0.1 * box.width, y: box.minY - 0.1 * box.height, width: 1.2 * box.width, height: 1.2 * box.height))
        }
        merged = merged.cleanedUp()   // stray blobs, holes, ragged edge (low-contrast garments)
        guard let b = merged.bounds else { throw CutoutError.noSubject }
        // Erode 1 px so the soft edge does not leave a halo.
        let margin = max(2, Int(max(b.width, b.height) * 0.03))
        guard let cut = Compositor.cutout(of: image, mask: merged.eroded(by: 1), margin: margin) else { throw CutoutError.renderFailed }
        return CutoutResult(cutout: cut, mask: merged.resized(maxSide: 256), candidates: candidates, chosen: chosen, needsChoice: needsChoice, session: self)
    }
}

/// Vision foreground instance masks, scored (see `SubjectSelector`) instead of merged.
public struct VisionCutoutService: CutoutProviding {
    public init() {}

    public func cutout(from image: CGImage, box: CGRect?) async throws -> CutoutResult {
        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        try handler.perform([request])
        guard let obs = request.results?.first, !obs.allInstances.isEmpty else { throw CutoutError.noSubject }

        // Vision numbers instances from 1; keep our index = position, with empty slots for failures.
        var masks: [Mask] = []
        for instance in obs.allInstances.sorted() {
            let pb = try obs.generateScaledMaskForImage(forInstances: IndexSet(integer: instance), from: handler)
            masks.append(Mask(pixelBuffer: pb) ?? Mask(width: image.width, height: image.height, pixels: [UInt8](repeating: 0, count: image.width * image.height)))
        }
        return try CutoutSession(image: image, instances: masks, box: box).initial()
    }
}
