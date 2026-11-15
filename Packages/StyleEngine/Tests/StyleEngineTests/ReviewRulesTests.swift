import Testing
@testable import StyleEngine

@Test func colourChoicesStartWithTheNameThenTwoNearest() {
    let c = ColorName.choices(first: .navy, hex: "1F2A44")
    #expect(c.count == 3 && c[0] == .navy && !c.dropFirst().contains(.navy) && !c.contains(.multicolor))
}

@Test func needsCheckMatchesEmptyFieldsAndUnknownFabric() {
    var t = ItemTags()
    #expect(t.needsCheck(.fabric) && t.needsCheck(.collar) && t.needsCheck(.dressCodes) && !t.needsCheck(.setRole))
    t.fabric = .unknown; t.dressCodes = []
    #expect(t.needsCheck(.fabric) && t.needsCheck(.dressCodes))
    t.fabric = .cotton; t.dressCodes = [.casual]
    #expect(!t.needsCheck(.fabric) && !t.needsCheck(.dressCodes))
}
