import Foundation
import StyleEngine
import os
@testable import AIStylist

/// Parser for tests: canned intent or error. Never the real model.
final class FakeIntentParser: IntentParser, @unchecked Sendable {
    struct Boom: Error {}
    var version = "fake-intent-1"
    var result: Result<OccasionIntent, Error>
    private let log = OSAllocatedUnfairLock(initialState: (calls: 0, messages: [String](), previous: [OccasionIntent?](), recent: [[String]]()))
    var calls: Int { log.withLock { $0.calls } }
    var messages: [String] { log.withLock { $0.messages } }
    var previous: [OccasionIntent?] { log.withLock { $0.previous } }
    var recent: [[String]] { log.withLock { $0.recent } }
    init(_ result: Result<OccasionIntent, Error> = .success(OccasionIntent(occasion: .festival, timeOfDay: .evening, setting: .indoor))) { self.result = result }

    func parse(message: String, previous: OccasionIntent?, recent: [String]) async throws -> OccasionIntent {
        log.withLock { $0.calls += 1; $0.messages.append(message); $0.previous.append(previous); $0.recent.append(recent) }
        return try result.get()
    }
}
