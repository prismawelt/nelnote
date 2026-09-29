import XCTest

final class NavigationTests: XCTestCase {
    @MainActor
    func testRapidTabChangesSwipesAndWidgetDeepLink() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()
        XCTAssertTrue(app.buttons["dock-4"].waitForExistence(timeout: 10))
        // Wait for the automatically dismissing intro before touching the dock.
        let book = app.buttons["dock-4"]
        book.tap()
        if !app.staticTexts["category-BOOK"].waitForExistence(timeout: 3) { book.tap() }
        XCTAssertTrue(app.staticTexts["category-BOOK"].waitForExistence(timeout: 5))
        for index in [0, 3, 1, 4, 0] { app.buttons["dock-\(index)"].tap() }
        XCTAssertTrue(app.staticTexts["category-GAME"].waitForExistence(timeout: 5))
        app.swipeLeft()
        XCTAssertTrue(app.staticTexts["category-ANIME"].waitForExistence(timeout: 5))
        app.swipeRight()
        XCTAssertTrue(app.staticTexts["category-GAME"].waitForExistence(timeout: 5))

        // Launching a URL for a deleted record must remain safe.
        if #available(iOS 16.4, *) {
            app.open(URL(string: "nelnote://item?id=deleted-record")!)
            XCTAssertTrue(app.staticTexts["진행 중 0개"].waitForExistence(timeout: 5))
        }
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "home-after-navigation"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
