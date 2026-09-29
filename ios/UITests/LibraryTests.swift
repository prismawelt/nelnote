import XCTest

final class LibraryTests: XCTestCase {
    @MainActor
    func testThousandItemsRemainSearchableAndNewStatusesAreVisible() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-large-library"]
        app.launch()
        let tab = app.buttons["dock-1"]
        XCTAssertTrue(tab.waitForExistence(timeout: 10))
        tab.tap()
        if !app.staticTexts["category-ANIME"].waitForExistence(timeout: 3) { tab.tap() }
        let search = app.textFields["category-search"]
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText("Library 0999")
        XCTAssertTrue(app.staticTexts["Library 0999"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["다음 시즌 대기"].exists)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "thousand-record-library-search"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    @MainActor
    func testObsidianConnectionControlsAreAvailable() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()
        let settings = app.buttons["settings-open"]
        XCTAssertTrue(settings.waitForExistence(timeout: 10))
        settings.tap()
        if !app.buttons["obsidian-connect"].waitForExistence(timeout: 3) { settings.tap() }
        XCTAssertTrue(app.buttons["obsidian-connect"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Obsidian 연결"].exists)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "obsidian-connection-settings"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
}
