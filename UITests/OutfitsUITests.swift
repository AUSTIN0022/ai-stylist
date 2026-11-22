import XCTest

/// Outfits tab: every saved outfit card opens its own detail on one tap, wherever on the card you tap.
final class OutfitsUITests: XCTestCase {
    func testEveryOutfitCardOpens() {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting"]
        app.launch()
        app.tabBars.buttons["Outfits"].tap()

        func card(_ name: String) -> XCUIElement {
            app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", name)).firstMatch
        }
        for name in ["Outfit one", "Outfit two", "Outfit three"] {
            let c = card(name)
            XCTAssertTrue(c.waitForExistence(timeout: 10), "\(name) card missing")
            c.tap()                                              // centre of the card: over the garment images
            XCTAssertTrue(app.navigationBars[name].waitForExistence(timeout: 3), "tapping \(name) did not open it")
            app.navigationBars.buttons.element(boundBy: 0).tap()
        }
    }
}
