import XCTest

/// Wardrobe: a category's "View all" page has a "+" that adds straight into that category.
final class WardrobeUITests: XCTestCase {
    func testViewAllPageHasAnAddButtonForThatCategory() {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting"]
        app.launch()

        let viewAll = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "View all"))
        XCTAssertTrue(viewAll.element(boundBy: 0).waitForExistence(timeout: 10))
        viewAll.element(boundBy: 1).tap()                                    // Tops, Bottoms, Footwear: the second is Bottoms
        XCTAssertTrue(app.navigationBars["Bottom"].waitForExistence(timeout: 5),
                      "bars: \(app.navigationBars.allElementsBoundByIndex.map { $0.identifier }) viewAll: \(viewAll.allElementsBoundByIndex.map { $0.label })")

        let add = app.buttons["Add to Bottom"]
        XCTAssertTrue(add.waitForExistence(timeout: 5), "no add button on the Bottom page")
        add.tap()
        XCTAssertTrue(app.buttons["Take photos"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Photo library"].exists)
    }

    func testWardrobeHasOneAddButton() {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting"]
        app.launch()
        let add = app.buttons["Add items"]
        XCTAssertTrue(add.waitForExistence(timeout: 10))
        add.tap()
        XCTAssertTrue(app.buttons["Take photos"].waitForExistence(timeout: 5))
    }
}
