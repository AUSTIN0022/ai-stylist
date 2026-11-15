import Foundation
import FoundationModels
import StyleEngine
import os

/// What the model fills in. Every field is optional (nil = not mentioned); plain code merges it (`IntentMerge`).
@Generable struct GeneratedIntent {
    @Guide(description: "The kind of occasion", .anyOf(Occasion.allCases.map(\.rawValue)))
    var occasion: String?
    @Guide(description: "The dress code, only if the message states or clearly implies one")
    var dressCode: DressCode?
    @Guide(description: "Lowest formality 1 (very casual) to 5 (very formal), only if the message changes it", .range(1...5))
    var formalityMin: Int?
    @Guide(description: "Highest formality 1 to 5. 'More casual' lowers it.", .range(1...5))
    var formalityMax: Int?
    @Guide(description: "When the event is", .anyOf(TimeOfDay.allCases.map(\.rawValue)))
    var timeOfDay: String?
    @Guide(description: "Where the event is", .anyOf(VenueSetting.allCases.map(\.rawValue)))
    var setting: String?
    @Guide(description: "The weather, only if mentioned", .anyOf(WeatherFeel.allCases.map(\.rawValue)))
    var weatherFeel: String?
    @Guide(description: "true if the user wants Indian clothes, false if they do not")
    var preferIndian: Bool?
    @Guide(description: "Any of fireworks, lotsOfWalking, religiousSite, photoHeavy that apply. Crackers or fireworks outdoors: fireworks.")
    var flags: [String]?
    @Guide(description: "Colours or clothing types the user does not want, e.g. black, jeans, chinos")
    var avoid: [String]?

    var parsed: ParsedIntent {
        ParsedIntent(occasion: occasion.flatMap(Occasion.init(rawValue:)), dressCode: dressCode,
                     formalityMin: formalityMin, formalityMax: formalityMax,
                     timeOfDay: timeOfDay.flatMap(TimeOfDay.init(rawValue:)), setting: setting.flatMap(VenueSetting.init(rawValue:)),
                     weatherFeel: weatherFeel.flatMap(WeatherFeel.init(rawValue:)), preferIndian: preferIndian,
                     flags: flags?.compactMap(IntentFlag.init(rawValue:)), avoid: avoid)
    }
}

/// Apple adapter for `IntentParser`: on-device model, one fresh session per message, greedy. Logging is done by the caller (`AICall.record`).
final class FoundationModelsIntentParser: IntentParser, TokenReporting, ProviderReporting, @unchecked Sendable {
    let providerName = AppleOnDeviceProvider.name
    let version = "fm-intent-1"
    private let tokens = OSAllocatedUnfairLock<Int?>(initialState: nil)
    var lastTokenCount: Int? { tokens.withLock { $0 } }

    static let instructions = """
        Turn the user's message into an outfit request. Choose only from the allowed values. \
        If the message changes an earlier request, keep everything it does not mention. \
        Glossary: sangeet, haldi, mehendi mean weddingGuest. puja and temple mean puja. Diwali and Holi mean festival.
        """

    func parse(message: String, previous: OccasionIntent?, recent: [String]) async throws -> OccasionIntent {
        if let reason = AppleOnDeviceProvider.unavailableReason() { throw AIUnavailable(reason: reason) }
        tokens.withLock { $0 = nil }
        let session = LanguageModelSession(instructions: Self.instructions)
        let r = try await session.respond(to: Self.prompt(message: message, previous: previous, recent: recent), generating: GeneratedIntent.self,
                                          options: GenerationOptions(samplingMode: .greedy))
        let total = r.usage.totalTokenCount
        tokens.withLock { $0 = total }
        return IntentMerge.merge(r.content.parsed, previous: previous, message: message)
    }

    /// Previous intent as one line, the last two user messages, then the new message.
    static func prompt(message: String, previous: OccasionIntent?, recent: [String]) -> String {
        var p = ""
        if let previous { p += "Earlier request: \(line(previous))\n" }
        if !recent.isEmpty { p += "Earlier messages: " + recent.suffix(2).map { "\"\($0)\"" }.joined(separator: ", ") + "\n" }
        return p + "New message: \(message)"
    }

    static func line(_ i: OccasionIntent) -> String {
        var parts = ["occasion \(i.occasion.rawValue)", "time \(i.timeOfDay.rawValue)", "setting \(i.setting.rawValue)", "weather \(i.weatherFeel.rawValue)"]
        if let d = i.dressCode { parts.append("dress code \(d.rawValue)") }
        if let lo = i.formalityMin, let hi = i.formalityMax { parts.append("formality \(lo) to \(hi)") }
        if i.preferIndian { parts.append("prefers Indian wear") }
        if !i.flags.isEmpty { parts.append("flags " + i.flags.map(\.rawValue).sorted().joined(separator: ", ")) }
        let avoid = i.avoid.map { a -> String in if case .colour(let c) = a { c.rawValue } else if case .subcategory(let s) = a { s.rawValue } else { "" } }
        if !avoid.isEmpty { parts.append("avoid " + avoid.joined(separator: ", ")) }
        return parts.joined(separator: ", ")
    }
}
