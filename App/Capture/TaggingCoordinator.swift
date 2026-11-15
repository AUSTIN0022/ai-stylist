import CoreGraphics
import Foundation
import StyleEngine
import WardrobeImaging

/// Runs the live tagging of review photos: one background task per photo, the wait with a timeout, and the A, B, C calls on a stored cut-out.
/// It knows nothing about `Photo`; the review model decides what each result means for a page.
@MainActor final class TaggingCoordinator {
    let tagger: any ItemTagger
    /// How long one photo may wait for the AI before the review opens with what is there.
    var timeout: Duration = .seconds(30)
    private var live: [UUID: Task<Void, Never>] = [:]
    private var tasks: [Task<Void, Never>] = []

    init(tagger: any ItemTagger) { self.tagger = tagger }

    /// nil when the model can run (or the tagger does not report availability).
    var unavailableReason: String? { (tagger as? AvailabilityReporting)?.unavailableReason }

    func start(_ id: UUID, _ work: @escaping @MainActor () async -> Void) {
        let t = Task { await work() }
        tasks.append(t); live[id] = t
    }
    func cancel(_ id: UUID) { live[id]?.cancel() }
    /// Waits for everything started so far (tests).
    func idle() async { var i = 0; while i < tasks.count { await tasks[i].value; i += 1 }; }

    /// The stored cut-out, shrunk for the model. nil when the file cannot be read.
    func cutoutImage(at url: URL) async -> CGImage? { await Task.detached(operation: { ImageCodec.thumbnail(at: url, maxPixel: 1024) }).value }

    /// Calls A, B, C in order; every call is logged through `sink`, `onIdentity` fires as soon as A answers.
    func run(_ cutout: CGImage, sink: @escaping @Sendable (AICallRecord) async -> Void, onIdentity: @Sendable (IdentityTags) async -> Void) async throws -> ItemTags {
        try await TaggingRun.run(tagger: tagger, cutout: cutout, sink: sink, onIdentity: onIdentity)
    }

    @MainActor private final class Once { var c: CheckedContinuation<Void, Never>?; func fire() { c?.resume(); c = nil } }
    /// Waits for a photo's tagging, at most `timeout`; on timeout it is cancelled and `onTimeout` runs (the photo shows as failed).
    func wait(for id: UUID, onTimeout: @escaping @MainActor () -> Void) async {
        guard let t = live[id] else { return }
        let once = Once(), limit = timeout
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            once.c = c
            let timer = Task {
                try? await Task.sleep(for: limit)
                guard !Task.isCancelled else { return }
                t.cancel()
                onTimeout()
                once.fire()
            }
            Task { await t.value; timer.cancel(); once.fire() }
        }
    }
}
