import Testing
import StyleEngine
@testable import WardrobeImaging

@Test func S1_U06_solidColour() {
    let r = ColorExtractor.extract(from: solid("B5522B"))
    #expect(r.hexes.count == 1)
    #expect(hexDistance(r.hexes[0], "B5522B") <= 3)
    #expect(r.names == [.rust])
}

@Test func S1_U07_transparentPixelsIgnored() {
    let img = makeImage(100, 100) { fill($0, "FF0000", 30, 30, 40, 40) }
    let r = ColorExtractor.extract(from: img)
    #expect(r.hexes.count == 1)
    #expect(hexDistance(r.hexes[0], "FF0000") <= 3)
    #expect(r.names == [.red])
}

@Test func S1_U08_twoColoursOrderedBySize() {
    let img = makeImage(100, 100) { fill($0, "1F2A44", 0, 0, 70, 100); fill($0, "F3EBDD", 70, 0, 30, 100) }
    #expect(ColorExtractor.extract(from: img).names == [.navy, .cream])
}

@Test func S1_U09_smallClusterDropped() {
    let img = makeImage(100, 100) { fill($0, "000000", 0, 0, 100, 100); fill($0, "FFFFFF", 40, 40, 22, 22) }
    #expect(ColorExtractor.extract(from: img).names == [.black])   // white is ~5% of pixels
}

@Test func S1_U10_atMostThree() {
    let img = makeImage(100, 100) {
        fill($0, "C0272D", 0, 0, 25, 100); fill($0, "2E8B57", 25, 0, 25, 100)
        fill($0, "2F5DA8", 50, 0, 25, 100); fill($0, "F2D43D", 75, 0, 25, 100)
    }
    let r = ColorExtractor.extract(from: img)
    #expect(r.hexes.count == 3)
    #expect(r.names == [.multicolor])     // more than 3 clusters pass the threshold
}

@Test func S1_U11_nameMappingTable() {
    let table: [(String, ColorName)] = [("000000", .black), ("FFFFFF", .white), ("1F2A44", .navy), ("F3EBDD", .cream),
                                        ("B5522B", .rust), ("556B2F", .olive), ("800020", .maroon)]
    for (hex, name) in table { #expect(ColorExtractor.name(forHex: hex) == name, "\(hex)") }
    for n in ColorName.allCases { if let h = n.referenceHex { #expect(ColorExtractor.name(forHex: h) == n) } }
}

@Test func S1_U12_navyIsNotBlack() {
    #expect(ColorExtractor.name(forHex: "1F2A44") == .navy)
    #expect(ColorExtractor.name(forHex: "0A0A0A") == .black)
}

@Test func S1_U13_edgePixelsIgnored() {
    let img = makeImage(100, 100) { fill($0, "FFFFFF", 0, 0, 100, 100); fill($0, "FF0000", 2, 2, 96, 96) }
    #expect(ColorExtractor.extract(from: img).names == [.red])
}
