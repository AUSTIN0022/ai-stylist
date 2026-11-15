import Foundation
import StyleEngine

/// The one seam between the app and an AI vendor (abstract factory). The app only ever talks to the three protocols
/// (`ItemTagger`, `IntentParser`, `NoteWriter`); a provider says which concrete adapters to use and whether they can run now.
/// To swap vendors, add another conforming type and change the one line in `AIStylistApp` (see docs/ARCHITECTURE.md).
protocol AIProvider: Sendable {
    /// Written to the AI call log as `provider` (e.g. "onDevice"). Per-call `model` comes from each adapter's `version`.
    var name: String { get }
    /// nil when the provider can run right now, else a printable reason (drives the no-AI mode and the Settings banner).
    var unavailableReason: String? { get }
    func makeTagger() -> any ItemTagger
    func makeIntentParser() -> any IntentParser
    func makeNoteWriter() -> any NoteWriter
}

/// Adapters implement this so the AI call log can name their provider; anything that doesn't is logged as on-device.
protocol ProviderReporting: Sendable { var providerName: String { get } }

/// What the AI call log writes as `provider` for an adapter (tagger, parser or writer).
func loggedProvider(of adapter: Any) -> String { (adapter as? ProviderReporting)?.providerName ?? AppleOnDeviceProvider.name }

/// Thrown by an adapter's call when its provider cannot run (the same text `AIProvider.unavailableReason` gives).
struct AIUnavailable: Error { let reason: String }
