import CoreGraphics
import Foundation
import StyleEngine
import os

/// Tagger for tests: canned answers, can throw, wait, hang, or report itself unavailable. Never the real model.
final class FakeTagger: ItemTagger, TokenReporting, AvailabilityReporting, @unchecked Sendable {
    struct Boom: Error {}
    var version = "fake-1"
    var identityResult: Result<IdentityTags, Error>
    var constructionResult: ItemTags = { var t = ItemTags(); t.fabric = .cotton; t.pattern = .solid; t.fit = .regular; t.length = .regular; t.collar = .spread; t.sleeve = .long; return t }()
    var usageResult: ItemTags = { var t = ItemTags(); t.dressCodes = [.casual]; t.formality = 2; t.seasons = [.summer]; t.warmth = 1; t.statement = .plain; t.caption = "A plain shirt"; return t }()
    /// Each call waits this long (cancellable).
    var delay: Duration = .zero
    /// Identity calls with these 1-based numbers throw.
    var failIdentityCalls: Set<Int> = []
    /// The nth identity call never returns (until cancelled).
    var hangOnIdentityCall: Int?
    var unavailableReason: String?

    private struct State { var identityCalls = 0, running = 0, maxRunning = 0, purposes: [String] = [] }
    private let state = OSAllocatedUnfairLock(initialState: State())
    var identityCalls: Int { state.withLock { $0.identityCalls } }
    var maxRunning: Int { state.withLock { $0.maxRunning } }
    var purposes: [String] { state.withLock { $0.purposes } }
    var lastTokenCount: Int? { 42 }

    init(version: String = "fake-1", result: Result<IdentityTags, Error> = .success(IdentityTags(category: .top, subcategory: .shirt, styleOrigin: .western))) {
        self.version = version; identityResult = result
    }

    private func enter(_ purpose: String) async throws {
        state.withLock { $0.running += 1; $0.maxRunning = max($0.maxRunning, $0.running); $0.purposes.append(purpose) }
    }
    private func leave() { state.withLock { $0.running -= 1 } }

    func identity(cutout: CGImage) async throws -> IdentityTags {
        try await enter("A"); defer { leave() }
        let n = state.withLock { $0.identityCalls += 1; return $0.identityCalls }
        if hangOnIdentityCall == n { try await Task.sleep(for: .seconds(3600)) }
        if delay > .zero { try await Task.sleep(for: delay) }
        if failIdentityCalls.contains(n) { throw Boom() }
        return try identityResult.get()
    }
    func construction(cutout: CGImage, category: StyleEngine.Category, subcategory: Subcategory) async throws -> ItemTags {
        try await enter("B"); defer { leave() }
        if delay > .zero { try await Task.sleep(for: delay) }
        return StyleEngine.construction(for: category, in: constructionResult)
    }
    func usage(cutout: CGImage, category: StyleEngine.Category, subcategory: Subcategory) async throws -> ItemTags {
        try await enter("C"); defer { leave() }
        if delay > .zero { try await Task.sleep(for: delay) }
        return usageResult
    }
}
