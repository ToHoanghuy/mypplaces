import XCTest

final class SmokeUITests: XCTestCase {
    func testLaunchShowsWelcomeOrTabs() {
        let app = XCUIApplication()
        app.launch()
        let welcome = app.buttons["welcome.signup"]
        let tabs = app.buttons["tab.0"]
        XCTAssertTrue(welcome.waitForExistence(timeout: 10) || tabs.exists)
    }
}
