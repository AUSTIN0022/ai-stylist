import Testing
@testable import StyleEngine

private func tags(_ f: (inout ItemTags) -> Void) -> ItemTags { var t = ItemTags(); f(&t); return t }
private var longLabel: LabelData { var l = LabelData(); l.composition = [FibrePart(percent: 60, fibre: "organic cotton"), FibrePart(percent: 40, fibre: "recycled polyester")]; return l }
private func prompt(_ t: ItemTags, _ c: [ColorName], label: LabelData? = nil) -> String { ProductShotPrompt.make(for: t, colours: c, label: label) }

@Test func S2_PS01_blackTeeTemplate() {
    let p = prompt(tags { $0.category = .top; $0.subcategory = .tshirt; $0.fabric = .cotton; $0.collar = .crew; $0.sleeve = .short; $0.pattern = .solid }, [.black])
    for s in ["short-sleeve", "black", "cotton", "crew-neck", "light grey background", "no person"] { #expect(p.contains(s), "missing \(s): \(p)") }
}
@Test func S2_PS02_buttonDownShirt() {
    let p = prompt(tags { $0.category = .top; $0.subcategory = .shirt; $0.fabric = .cotton; $0.collar = .buttonDown; $0.sleeve = .long }, [.white])
    #expect(p.contains("button-down collar") && p.contains("long sleeves"), Comment(rawValue: p))
}
@Test func S2_PS03_trousersAndFootwear() {
    let j = prompt(tags { $0.category = .bottom; $0.subcategory = .jeans; $0.fabric = .denim }, [.blue])
    #expect(j.contains("legs straight and parallel"))
    let s = prompt(tags { $0.category = .footwear; $0.subcategory = .sneakers }, [.white])
    #expect(s.lowercased().contains("side view of a pair of white sneakers"), Comment(rawValue: s))
    #expect(!s.contains("legs straight"))
}
@Test func S2_PS04_deterministicAndShort() {
    let t = tags { $0.category = .top; $0.subcategory = .hoodie; $0.fabric = .fleece }
    #expect(prompt(t, [.navy]) == prompt(t, [.navy]))
    for sub in Subcategory.allCases { for col in Collar.allCases { for sl in Sleeve.allCases { for pat in Pattern.allCases {
        let x = tags { $0.subcategory = sub; $0.collar = col; $0.sleeve = sl; $0.pattern = pat; $0.fabric = .cottonLinen; $0.fit = .relaxed }
        let p = ProductShotPrompt.make(for: x, colours: [.lightBlue, .mustard], hexes: ["9CC3E6", "C9A227"], label: longLabel)
        #expect(p.count <= 300, Comment(rawValue: "\(p.count): \(p)"))
    } } } }
}
@Test func S2_PS05_brandNeverInPrompt() {
    var l = LabelData(); l.brand = "Westside"; l.subBrand = "WES"; l.fabric = .linen
    for sub in Subcategory.allCases {
        let p = prompt(tags { $0.subcategory = sub }, [.red], label: l)
        #expect(!p.contains("Westside") && !p.contains("WES"))
    }
}

@Test func S2_PS11_colourPhrase() {
    #expect(ProductShotPrompt.colourPhrase(.navy, hex: "1F2A44") == "deep navy (#1F2A44)")
    #expect(ProductShotPrompt.colourPhrase(.white, hex: "EDEBE4") == "off-white (#EDEBE4)")
    #expect(ProductShotPrompt.colourPhrase(.white, hex: "FFFFFF") == "white (#FFFFFF)")
    #expect(ProductShotPrompt.colourPhrase(.black, hex: "111111") == "black (#111111)")
    #expect(ProductShotPrompt.colourPhrase(.red, hex: nil) == "red")
}
@Test func S2_PS11_textureAndSwatchSentence() {
    var l = LabelData(); l.composition = [FibrePart(percent: 100, fibre: "organic cotton")]
    let t = tags { $0.subcategory = .chinos; $0.fabric = .twill }
    let p = ProductShotPrompt.make(for: t, colours: [.white], hexes: ["EDEBE4"], label: l)
    let plain = ProductShotPrompt.make(for: t, colours: [.white], hexes: ["EDEBE4"], label: l, swatch: false)
    #expect(plain.contains("100% organic cotton twill") && plain.contains("off-white (#EDEBE4)"), Comment(rawValue: plain))
    #expect(p.contains("Match the") && p.contains("reference swatch") && p.count <= 300)
    #expect(!ProductShotPrompt.make(for: t, colours: [.white], hexes: ["EDEBE4"], label: l, swatch: false).contains("swatch"))
    #expect(p == ProductShotPrompt.make(for: t, colours: [.white], hexes: ["EDEBE4"], label: l))
}
@Test func S2_PS11_dropOrderKeepsColourAndShape() {
    // Long everything: wording shrinks first, then composition, pattern, swatch sentence, hex last; colour name and shape never.
    var l = LabelData(); l.composition = [FibrePart(percent: 55, fibre: "organic cotton"), FibrePart(percent: 45, fibre: "recycled polyester")]
    let t = tags { $0.subcategory = .shirt; $0.fabric = .cottonLinen; $0.collar = .mandarin; $0.sleeve = .long; $0.pattern = .colourBlock; $0.caption = "ribbed" }
    let p = ProductShotPrompt.make(for: t, colours: [.lightBlue, .mustard], hexes: ["9CC3E6", "C9A227"], label: l)
    #expect(p.count <= 300, Comment(rawValue: "\(p.count): \(p)"))
    #expect(p.contains("light blue") && p.contains("long sleeves") && p.contains("no person") && p.contains("light grey background"))
    #expect(!p.contains("organic cotton"), Comment(rawValue: p))   // composition is the first thing dropped
    var one = LabelData(); one.composition = [FibrePart(percent: 100, fibre: "organic cotton")]
    let chinos = tags { $0.subcategory = .chinos; $0.fabric = .cotton }
    #expect(ProductShotPrompt.make(for: chinos, colours: [.black], hexes: ["1A1A1A"], label: one).contains("100% organic cotton"))
}

// Device test (14 Nov): Image Playground refused the long 300-character sentence ("Try describing something different").
// It is built for short concept phrases, so the default sends 2-3 short positive phrases: no negatives, no hex, no "person".
@Test func S2_PS12_shortConceptsArePositiveAndShort() {
    let t = tags { $0.category = .top; $0.subcategory = .tshirt; $0.fabric = .cotton; $0.collar = .crew; $0.sleeve = .short }
    let c = ProductShotPrompt.shortConcepts(for: t, colours: [.black])
    #expect(!c.isEmpty && c.count <= 3)
    #expect(c.first == "black cotton t-shirt", Comment(rawValue: c.joined(separator: " | ")))
    for s in c {
        #expect(s.count <= 40, Comment(rawValue: s))
        for banned in ["no ", "#", "person", "mannequin", "match"] { #expect(!s.lowercased().contains(banned), Comment(rawValue: s)) }
    }
    #expect(c.contains { $0.contains("flat lay") } && c.contains { $0.contains("grey background") })
}
@Test func S2_PS13_shortConceptsPerShape() {
    let jeans = ProductShotPrompt.shortConcepts(for: tags { $0.category = .bottom; $0.subcategory = .jeans; $0.fabric = .denim }, colours: [.blue])
    #expect(jeans.first == "blue denim jeans")
    let shoes = ProductShotPrompt.shortConcepts(for: tags { $0.category = .footwear; $0.subcategory = .sneakers }, colours: [.white])
    #expect(shoes.first == "pair of white sneakers" && shoes.contains { $0.contains("side view") })
    let shirt = ProductShotPrompt.shortConcepts(for: tags { $0.category = .top; $0.subcategory = .shirt; $0.collar = .buttonDown; $0.sleeve = .long }, colours: [.maroon])
    #expect(shirt.first == "maroon button-down shirt", Comment(rawValue: shirt.joined(separator: " | ")))
    let noFabric = ProductShotPrompt.shortConcepts(for: tags { $0.category = .top; $0.subcategory = .hoodie; $0.fabric = .unknown }, colours: [.navy])
    #expect(noFabric.first == "navy hoodie")
}

// Device test (14 Nov): Austin's prompt worked in Image Playground where the 300-character one was refused:
// "Create a Front view e-commerce product photo of a dark maroon (#803F55) cotton short-sleeve tshirt, laid flat and symmetrical,
//  plain light grey background, soft shadow, no person, no text." This is now the default template.
@Test func S2_PS14_provenSentenceTemplate() {
    let tee = tags { $0.category = .top; $0.subcategory = .tshirt; $0.fabric = .cotton; $0.sleeve = .short }
    #expect(ProductShotPrompt.sentence(for: tee, colours: [.black], hexes: ["171D24"]) ==
            "Create a Front view e-commerce product photo of a black (#171D24) cotton short-sleeve tshirt, laid flat and symmetrical, plain light grey background, soft shadow, no person, no text.")
    let jeans = ProductShotPrompt.sentence(for: tags { $0.category = .bottom; $0.subcategory = .jeans; $0.fabric = .denim }, colours: [.blue], hexes: ["2B4A7A"])
    #expect(jeans.contains("denim jeans, laid flat with legs straight"), Comment(rawValue: jeans))
    let shoes = ProductShotPrompt.sentence(for: tags { $0.category = .footwear; $0.subcategory = .sneakers }, colours: [.white], hexes: [])
    #expect(shoes.hasPrefix("Create a side view e-commerce product photo of a pair of white sneakers"), Comment(rawValue: shoes))
    let shirt = ProductShotPrompt.sentence(for: tags { $0.category = .top; $0.subcategory = .shirt; $0.collar = .buttonDown; $0.sleeve = .long; $0.fabric = .cotton }, colours: [.maroon], hexes: ["803F55"])
    #expect(shirt.contains("cotton long-sleeve button-down shirt"), Comment(rawValue: shirt))
    for p in [jeans, shoes, shirt] { #expect(p.count <= 200, Comment(rawValue: p)); #expect(p.hasSuffix("no person, no text.")) }
}

private func t(_ f: (inout ItemTags) -> Void) -> ItemTags { var x = ItemTags(); f(&x); return x }

@Test func S2_PS15_templateShapeMapping() {
    #expect(ProductTemplate.shape(for: t { $0.category = .top; $0.subcategory = .tshirt; $0.sleeve = .short }) == .tshirtShort)
    #expect(ProductTemplate.shape(for: t { $0.category = .top; $0.subcategory = .tshirt; $0.sleeve = .long }) == .tshirtLong)
    #expect(ProductTemplate.shape(for: t { $0.category = .top; $0.subcategory = .sweater }) == .tshirtLong)
    #expect(ProductTemplate.shape(for: t { $0.category = .top; $0.subcategory = .shirt }) == .shirt)
    #expect(ProductTemplate.shape(for: t { $0.category = .top; $0.subcategory = .hoodie }) == .hoodie)
    #expect(ProductTemplate.shape(for: t { $0.category = .outerwear; $0.subcategory = .jacket }) == .jacket)
    #expect(ProductTemplate.shape(for: t { $0.category = .outerwear; $0.subcategory = .blazer }) == .jacket)
    for s in [Subcategory.jeans, .chinos, .trousers] { #expect(ProductTemplate.shape(for: t { $0.category = .bottom; $0.subcategory = s }) == .trousers) }
    #expect(ProductTemplate.shape(for: t { $0.category = .bottom; $0.subcategory = .shorts }) == .shorts)
    #expect(ProductTemplate.shape(for: t { $0.category = .footwear; $0.subcategory = .sneakers }) == .shoes)
    for s in [Subcategory.kurta, .saree, .dress] { #expect(ProductTemplate.shape(for: t { $0.subcategory = s }) == nil) }
}

@Test func S2_PS16_sourceSelectionRule() {
    let solid = t { $0.category = .top; $0.subcategory = .tshirt; $0.sleeve = .short; $0.pattern = .solid }
    #expect(ProductTemplate.source(for: solid, available: [.tshirtShort]) == .template(.tshirtShort))
    #expect(ProductTemplate.source(for: t { $0.category = .top; $0.subcategory = .tshirt; $0.sleeve = .short }, available: [.tshirtShort]) == .template(.tshirtShort))   // pattern missing
    var striped = solid; striped.pattern = .stripe
    #expect(ProductTemplate.source(for: striped, available: [.tshirtShort]) == .cutout)
    #expect(ProductTemplate.source(for: solid, available: [.hoodie]) == .cutout)   // no template for this shape
    #expect(ProductTemplate.source(for: t { $0.subcategory = .saree }, available: Set(TemplateShape.allCases)) == .cutout)
}

@Test func S2_PS17_defaultSentencesForTheFourReferenceItems() {
    #expect(ProductShotPrompt.sentence(for: t { $0.category = .top; $0.subcategory = .tshirt; $0.fabric = .cotton; $0.sleeve = .short }, colours: [.black], hexes: ["171D24"]) ==
            "Create a Front view e-commerce product photo of a black (#171D24) cotton short-sleeve tshirt, laid flat and symmetrical, plain light grey background, soft shadow, no person, no text.")
    #expect(ProductShotPrompt.sentence(for: t { $0.category = .top; $0.subcategory = .hoodie; $0.fabric = .fleece }, colours: [.navy], hexes: ["1F2A44"])
                .hasPrefix("Create a Front view e-commerce product photo of a "))
    #expect(ProductShotPrompt.templateSentence(for: .hoodie).contains("mid-grey") && ProductShotPrompt.templateSentence(for: .hoodie).hasSuffix("no person, no text."))
    #expect(Set(TemplateShape.allCases.map { ProductShotPrompt.templateSentence(for: $0) }).count == TemplateShape.allCases.count)
}

@Test func S2_PS20_sleeveWordAlwaysPresentAndAskedWhenMissing() {
    func tee(_ sl: Sleeve?) -> ItemTags { t { $0.category = .top; $0.subcategory = .tshirt; $0.fabric = .cotton; $0.sleeve = sl } }
    for (sl, w) in [(Sleeve.short, "short-sleeve"), (.long, "long-sleeve"), (.threeQuarter, "three-quarter-sleeve"), (.sleeveless, "sleeveless")] {
        let p = ProductShotPrompt.sentence(for: tee(sl), colours: [.white], hexes: [])
        #expect(p.contains("cotton \(w) tshirt"), Comment(rawValue: p))
        #expect(!ProductShotPrompt.needsSleeve(tee(sl)))
    }
    #expect(ProductShotPrompt.needsSleeve(tee(nil)))
    #expect(ProductShotPrompt.needsSleeve(t { $0.category = .outerwear; $0.subcategory = .jacket }))
    #expect(ProductShotPrompt.needsSleeve(t { $0.category = .onePiece; $0.subcategory = .dress }))
    #expect(!ProductShotPrompt.needsSleeve(t { $0.category = .bottom; $0.subcategory = .jeans }))
    #expect(!ProductShotPrompt.needsSleeve(t { $0.category = .footwear; $0.subcategory = .sneakers }))
    #expect(!ProductShotPrompt.needsSleeve(t { $0.category = .onePiece; $0.subcategory = .saree }))
    #expect(ProductShotPrompt.sentence(for: t { $0.category = .outerwear; $0.subcategory = .jacket; $0.sleeve = .long }, colours: [.black], hexes: []).contains("long-sleeve jacket"))
}
