import XCTest

/// XCUITest smoke: app launches to the Pulse tab.
final class SmokeUITests: XCTestCase {
    func testLaunchShowsPulseTab() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 10))
    }
}
