import Foundation
import Testing
@testable import StyleEngine

@Suite("S4 note validator") struct NoteValidatorTests {
    let outfit = [mk("Rust shirt", .top, .shirt, [.rust]), mk("Black chinos", .bottom, .chinos, [.black]),
                  mk("Cream sneakers", .footwear, .sneakers, [.cream])]

    @Test("S4-U09 absent item type is rejected") func u09() {
        #expect(!NoteValidator.isValid("The jacket adds polish for the evening.", for: outfit))
        #expect(NoteValidator.offences("Pair it with the jacket", for: outfit) == ["jacket"])
    }
    @Test("S4-U10 absent colour is rejected") func u10() {
        #expect(!NoteValidator.isValid("The navy tones keep it calm.", for: outfit))
        #expect(!NoteValidator.isValid("A light blue touch.", for: outfit))
    }
    @Test("S4-U11 valid note is accepted") func u11() {
        #expect(NoteValidator.isValid("The rust shirt and black chinos feel warm and festive, with cream sneakers to keep it relaxed.", for: outfit))
        #expect(NoteValidator.isValid("A smart-casual dress code works well here.", for: outfit))   // "dress code" is not a dress
    }
    @Test("plurals, grey/gray and t-shirt spellings") func spellings() {
        let o = [mk("Grey tee", .top, .tshirt, [.grey]), mk("Jeans", .bottom, .jeans, [.navy]), mk("Shoes", .footwear, .sneakers, [.white])]
        #expect(NoteValidator.isValid("A gray t-shirt with jeans and sneakers in navy and white.", for: o))
        #expect(!NoteValidator.isValid("The chinos would also work.", for: o))
    }
    @Test("note prompt rows list slot, name, colour") func prompt() {
        let text = NotePrompt.text(intent: .init(occasion: .festival, timeOfDay: .evening, setting: .indoor),
                                   outfits: [[(.top, outfit[0]), (.bottom, outfit[1])]])
        #expect(text.contains("Festival") && text.contains("1.") && text.contains("top: Rust shirt (rust"))
    }
}
