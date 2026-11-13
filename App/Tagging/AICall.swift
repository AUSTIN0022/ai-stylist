import Foundation

/// One AI call as plain data (Sendable), turned into an `AIRequestLog` row on the main actor.
struct AICallRecord: Sendable {
    var purpose: String, provider: String, model: String
    var start: Date, seconds: Double
    var tokens: Int?
    var success: Bool
    var error: String?
}

func describe(_ error: Error) -> String {
    let d = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
    return d.isEmpty ? "Unknown error" : d
}

/// The wrapper every AI call goes through: one record per call, success or not; errors are re-thrown.
enum AICall {
    static func record<T>(purpose: String, provider: String = "onDevice", model: String, tokens: (@Sendable () -> Int?)? = nil,
                          sink: (AICallRecord) async -> Void, _ body: () async throws -> T) async throws -> T {
        let clock = ContinuousClock(), began = clock.now, date = Date()
        func make(success: Bool, error: String?) -> AICallRecord {
            AICallRecord(purpose: purpose, provider: provider, model: model, start: date, seconds: max(1e-6, (clock.now - began) / .seconds(1)),
                         tokens: success ? tokens?() : nil, success: success, error: error)
        }
        do {
            let v = try await body()
            await sink(make(success: true, error: nil))
            return v
        } catch {
            await sink(make(success: false, error: describe(error)))
            throw error
        }
    }
}
