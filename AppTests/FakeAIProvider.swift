import StyleEngine
@testable import AIStylist

/// An `AIProvider` for tests: hands out the fakes (or ones you pass in). Never the real model.
struct FakeAIProvider: AIProvider {
    var name = "fake"
    var unavailableReason: String?
    var tagger: any ItemTagger = FakeTagger()
    var parser: any IntentParser = FakeIntentParser()
    var writer: any NoteWriter = FakeNoteWriter()

    func makeTagger() -> any ItemTagger { tagger }
    func makeIntentParser() -> any IntentParser { parser }
    func makeNoteWriter() -> any NoteWriter { writer }
}
