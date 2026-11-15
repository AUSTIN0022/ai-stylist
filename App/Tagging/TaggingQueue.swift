import CoreGraphics
import Foundation
import StyleEngine
import SwiftData
import WardrobeImaging

struct TimedOut: LocalizedError {
    let after: Duration
    var errorDescription: String? { "Timed out after \(Int(after / .seconds(1))) s" }
}

/// Tags saved items one at a time, in the background. Items are `tagging` until done, then `ready` or `failed`.
/// `start()` re-queues everything left in `tagging` (app launch); `retry` is the manual "Try again". No automatic retry.
/// It uses its own ModelContext on the app's container; the UI sees saved changes through @Query.
actor TaggingQueue {
    private let container: ModelContainer
    private let store: ImageStore
    private let tagger: any ItemTagger
    private let timeout: Duration
    private let thermalOK: @Sendable () -> Bool
    private let context: ModelContext
    private var pending: [UUID] = []
    private var current: UUID?
    private var worker: Task<Void, Never>?
    private var stopping = false
    private var rows: [AICallRecord] = []
    /// Items finished or failed since the queue was last empty, and the batch size: "N of M".
    private(set) var done = 0, total = 0

    init(container: ModelContainer, store: ImageStore, tagger: any ItemTagger, timeout: Duration = .seconds(90),
         thermalOK: @escaping @Sendable () -> Bool = { ProcessInfo.processInfo.thermalState.rawValue < ProcessInfo.ThermalState.serious.rawValue }) {
        self.container = container; self.store = store; self.tagger = tagger; self.timeout = timeout; self.thermalOK = thermalOK
        context = ModelContext(container)
        context.autosaveEnabled = false
    }

    var pendingCount: Int { pending.count + (current == nil ? 0 : 1) }
    private var unavailable: String? { (tagger as? AvailabilityReporting)?.unavailableReason }

    /// App launch: everything still `tagging` goes back in the queue.
    func start() {
        let stuck = ((try? context.fetch(FetchDescriptor<Item>())) ?? []).filter { $0.status == .tagging }.sorted { $0.createdAt < $1.createdAt }
        enqueue(stuck.map(\.id))
    }

    func enqueue(_ ids: [UUID]) {
        stopping = false
        let new = ids.filter { $0 != current && !pending.contains($0) }
        pending += new; total += new.count
        kick()
    }

    /// "Try again" on a failed item, or a re-tag of a ready one. aiRaw is replaced, overrides stay.
    func retry(_ id: UUID) {
        guard let item = fetch(id) else { return }
        item.status = .tagging; item.lastError = nil
        try? context.save()
        enqueue([id])
    }

    /// "Tag N untagged items": ready items that never got an AI answer. Returns how many were queued (0 while the model is off).
    @discardableResult func tagUntagged() -> Int {
        guard unavailable == nil else { return 0 }
        let items = ((try? context.fetch(FetchDescriptor<Item>())) ?? []).filter { $0.status == .ready && $0.aiRawData == nil }.sorted { $0.createdAt < $1.createdAt }
        for i in items { i.status = .tagging }
        try? context.save()
        enqueue(items.map(\.id))
        return items.count
    }

    /// Finishes the item in hand, leaves the rest as `tagging` (they resume with `start()`).
    func stop() { stopping = true }

    func waitUntilIdle() async { while let w = worker { await w.value } }

    private func kick() {
        guard worker == nil else { return }
        worker = Task { await self.loop() }
    }

    private func loop() async {
        while !pending.isEmpty, !stopping {
            // Back-to-back model calls heat the phone: wait while the system reports serious thermal state.
            while !thermalOK() { try? await Task.sleep(for: .seconds(10)) }
            let id = pending.removeFirst()
            current = id
            await process(id)
            current = nil; done += 1
        }
        if pending.isEmpty { done = 0; total = 0 }
        worker = nil
    }

    private func fetch(_ id: UUID) -> Item? { try? context.fetch(FetchDescriptor<Item>(predicate: #Predicate { $0.id == id })).first }
    private func add(_ r: AICallRecord) { rows.append(r) }

    private func process(_ id: UUID) async {
        guard let item = fetch(id) else { return }
        guard unavailable == nil else {   // model off: the item stays usable, untagged
            item.status = .ready; item.lastError = nil; try? context.save(); return
        }
        item.status = .tagging; item.lastError = nil
        let url = store.url(for: item.cutoutFile ?? item.originalFile, id: id)
        rows = []
        if let img = ImageCodec.thumbnail(at: url, maxPixel: 1024) {
            do {
                let (tagger, limit) = (self.tagger, timeout)
                let raw = try await Self.withTimeout(limit) {
                    try await TaggingRun.run(tagger: tagger, cutout: img, sink: { await self.add($0) })
                }
                item.replaceRaw(raw, version: tagger.version, context: nil)
                item.status = .ready
            } catch {
                item.status = .failed; item.lastError = describe(error)
            }
        } else { item.status = .failed; item.lastError = "The item's image could not be read." }
        rows.forEach { context.insert(AIRequestLog($0)) }
        rows = []
        try? context.save()
    }

    // ponytail: if the model call ignores cancellation the group waits for it; the timeout only fires for cancellable calls.
    static func withTimeout<T: Sendable>(_ limit: Duration, _ op: @escaping @Sendable () async throws -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { g in
            g.addTask { try await op() }
            g.addTask { try await Task.sleep(for: limit); throw TimedOut(after: limit) }
            defer { g.cancelAll() }
            return try await g.next()!
        }
    }
}
