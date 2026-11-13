import Testing
import StyleEngine
@testable import WardrobeImaging

@Test func S1B_U01_bluishBlackIsBlackAndAmbiguous() {
    let c = ColorExtractor.classify(hex: "151B26")
    #expect(c.name == .black && c.ambiguous)
}
@Test func S1B_U02_navyStaysNavy() { #expect(ColorExtractor.name(forHex: "1F2A44") == .navy) }
@Test func S1B_U03_nearBlack() { #expect(ColorExtractor.name(forHex: "0A0A0A") == .black) }
@Test func S1B_U04_darkBrownIsNotBlack() { #expect(ColorExtractor.name(forHex: "3B2416") == .brown) }
@Test func S1B_U05_whiteAndCream() {
    #expect(ColorExtractor.name(forHex: "FAFAF8") == .white)
    #expect(ColorExtractor.name(forHex: "F3EBDD") == .cream)
}
@Test func S1B_U06_ambiguousFlag() {
    #expect(ColorExtractor.classify(hex: "CDB089").ambiguous)          // midway beige / tan
    #expect(!ColorExtractor.classify(hex: "B5522B").ambiguous)
    #expect(ColorExtractor.extract(from: solid("151B26")).ambiguous == [true])
}
@Test func S1B_U03b_clearBlackAndWhiteAreNotAmbiguous() {
    #expect(!ColorExtractor.classify(hex: "000000").ambiguous)
    #expect(!ColorExtractor.classify(hex: "0A0A0A").ambiguous)
    #expect(!ColorExtractor.classify(hex: "FFFFFF").ambiguous)
    #expect(ColorExtractor.extract(from: solid("0A0A0A")).ambiguous == [false])
}
