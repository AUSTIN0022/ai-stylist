import Foundation
import os
@testable import AIStylist

/// Note writer for tests: canned notes, can throw or wait (cancellable). Never the real model.
final class FakeNoteWriter: NoteWriter, @unchecked Sendable {
    struct Boom: Error {}
    var version = "fake-note-1"
    var result: Result<[String], Error>
    var delay: Duration = .zero
    private let log = OSAllocatedUnfairLock(initialState: (calls: 0, prompt: ""))
    var calls: Int { log.withLock { $0.calls } }
    var lastPrompt: String { log.withLock { $0.prompt } }
    init(_ result: Result<[String], Error> = .success(["A relaxed evening look.", "Easy and comfortable.", "Simple and put together."])) { self.result = result }

    func notes(prompt: String, count: Int) async throws -> [String] {
        log.withLock { $0.calls += 1; $0.prompt = prompt }
        if delay > .zero { try await Task.sleep(for: delay) }
        return Array(try result.get().prefix(count))
    }
}
