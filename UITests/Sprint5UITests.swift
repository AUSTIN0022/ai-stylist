import XCTest

/// S5-UI01: Outfits -> New outfit, tap three drawer items to add them, Save, reopen the outfit: three items are there.
/// Runs against `-uiTesting` (in-memory seeded wardrobe, no AI).
final class Sprint5UITests: XCTestCase {
    func testS5_UI01_buildSaveReopen() {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting"]
        app.launch()

        app.tabBars.buttons["Outfits"].tap()
        app.buttons["New outfit"].tap()

        func pick(_ category: String?, _ item: String) {
            if let category {
                app.buttons["category-picker"].tap()
                app.buttons[category].tap()
            }
            let cell = app.descendants(matching: .any)["drawer-\(item)"]
            XCTAssertTrue(cell.waitForExistence(timeout: 5), "\(item) not in the drawer")
            cell.tap()
        }
        pick(nil, "Rust shirt")
        pick("Bottoms", "Black chinos")
        pick("Footwear", "White sneakers")

        let save = app.buttons["Save"]
        XCTAssertTrue(save.isEnabled)
        save.tap()

        // Back on the Outfits tab: the saved outfit is there; open it.
        func element(containing text: String) -> XCUIElement {
            app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
        }
        let card = element(containing: "My outfit")
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        card.tap()

        for name in ["Rust shirt", "Black chinos", "White sneakers"] {
            XCTAssertTrue(element(containing: name).waitForExistence(timeout: 5), "\(name) missing after reopening")
        }
    }
}
