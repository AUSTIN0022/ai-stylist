import FoundationModels
import StyleEngine

/// Apple Foundation Models (on-device, free): the prototype's only provider. Hands out the Apple adapters.
struct AppleOnDeviceProvider: AIProvider {
    static let name = "onDevice"
    var name: String { Self.name }
    var unavailableReason: String? { Self.unavailableReason() }

    func makeTagger() -> any ItemTagger { FoundationModelsTagger() }
    func makeIntentParser() -> any IntentParser { FoundationModelsIntentParser() }
    func makeNoteWriter() -> any NoteWriter { FoundationModelsNoteWriter() }

    /// nil when the system model is usable, else a printable reason. Also used by the Sprint 0 spike code.
    static func unavailableReason() -> String? {
        switch SystemLanguageModel.default.availability {
        case .available: nil
        case .unavailable(.deviceNotEligible): "Device not eligible for Apple Intelligence."
        case .unavailable(.appleIntelligenceNotEnabled): "Apple Intelligence is turned off in Settings."
        case .unavailable(.modelNotReady): "Model not ready: still downloading. Stay on Wi-Fi and power."
        case .unavailable(let other): "Model unavailable: \(other)"
        }
    }
}
