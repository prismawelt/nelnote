import XCTest

final class BookProgressTests: XCTestCase {
    @MainActor
    func testNumberPadEntryDoesNotOpenTheEditorAndFinishCommitsTheDraft() throws {
        let app = XCUIApplication()
        app.launch()
        let bookTab = app.buttons["dock-4"]
        XCTAssertTrue(bookTab.waitForExistence(timeout: 10))
        bookTab.tap()
        if !app.staticTexts["category-BOOK"].waitForExistence(timeout: 3) { bookTab.tap() }
        XCTAssertTrue(app.staticTexts["category-BOOK"].waitForExistence(timeout: 5))
        app.buttons["추가"].tap()
        let title = app.textFields["editor-title"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        title.tap()
        title.typeText("Book input test")
        app.segmentedControls["editor-status"].buttons["진행중"].tap()
        let total = app.textFields["editor-total"]
        total.tap()
        total.typeText("300")
        let save = app.buttons["editor-save"]
        for _ in 0..<3 where !save.isHittable { app.swipeUp() }
        save.tap()

        let field = app.textFields.matching(NSPredicate(format: "identifier BEGINSWITH %@", "book-progress-")).firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.keyboards.keys["1"].exists)
        XCTAssertFalse(app.staticTexts["작품 수정"].exists)
        field.typeText("123")
        app.buttons["입력 완료"].tap()
        XCTAssertEqual(field.value as? String, "123")
        XCTAssertTrue(app.staticTexts["123 / 300p"].exists)

        field.tap()
        field.typeText("300")
        app.buttons["입력 완료"].tap()
        XCTAssertTrue(field.exists)
        XCTAssertEqual(field.value as? String, "300")
        let finish = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "item-quick-")).firstMatch
        XCTAssertEqual(finish.label, "완독")
        XCTAssertLessThan(field.frame.maxX, finish.frame.minX)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "book-inline-page-and-finish"
        attachment.lifetime = .keepAlways
        add(attachment)

        // Finishing while the keyboard is open must commit the new page before the undo snapshot.
        field.tap()
        field.typeText("250")
        finish.tap()
        XCTAssertFalse(field.exists)
        app.buttons["되돌리기"].tap()
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        XCTAssertEqual(field.value as? String, "250")
        finish.tap()
        XCTAssertFalse(field.exists)
    }
}
