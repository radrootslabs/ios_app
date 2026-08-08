import XCTest

final class RadrootsRootShellUITests: XCTestCase {
    @MainActor
    func testShellExposesExactlyTodayAndAddBottomTabs() {
        let app = XCUIApplication()
        app.launchEnvironment["RADROOTS_IOS_UI_TEST_SHELL"] = "1"
        app.launch()

        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 5))
        XCTAssertEqual(tabBar.buttons.count, 2)
        XCTAssertTrue(tabBar.buttons["Today"].exists)
        XCTAssertTrue(tabBar.buttons["Add"].exists)
        XCTAssertFalse(tabBar.buttons["Capture"].exists)
        XCTAssertFalse(tabBar.buttons["Activity"].exists)
        XCTAssertFalse(tabBar.buttons["Settings"].exists)

        tabBar.buttons["Add"].tap()
        XCTAssertTrue(app.otherElements["radroots.add.root"].waitForExistence(timeout: 2))
        tabBar.buttons["Today"].tap()
        XCTAssertTrue(app.otherElements["radroots.today.root"].waitForExistence(timeout: 2))
    }
}
