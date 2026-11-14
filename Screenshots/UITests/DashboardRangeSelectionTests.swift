import XCTest

@MainActor
final class DashboardRangeSelectionTests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testSelectionStaysOnTappedRangeWithEmptyWeek() {
        checkSelection(scenario: "emptyWeek", titles: ["7 Days", "30 Days", "90 Days", "All"])
    }

    func testSelectionStaysOnTappedRangeWithMergedOptions() {
        checkSelection(scenario: "gap", titles: ["7 Days", "90 Days", "All"])
    }

    func testSelectionStaysOnTappedRangeWithAllOptions() {
        checkSelection(scenario: "long", titles: ["7 Days", "30 Days", "90 Days", "All"])
    }

    private func checkSelection(scenario: String, titles: [String]) {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = [
            "-UITestMode", "-UITestAnimations", "-DashboardScenario", scenario,
            "-AppleLanguages", "(en)", "-AppleLocale", "en_US"
        ]
        app.launch()
        defer { app.terminate() }
        XCTAssertTrue(app.descendants(matching: .any)
            .matching(identifier: "screenshot.ready.home").firstMatch.waitForExistence(timeout: 20))
        let picker = app.segmentedControls.firstMatch
        XCTAssertTrue(picker.waitForExistence(timeout: 5))

        for title in titles.reversed() + titles {
            XCTAssertEqual(picker.buttons.allElementsBoundByIndex.map(\.label), titles)
            let button = picker.buttons[title]
            button.tap()
            XCTAssertTrue(button.isSelected, "The tapped range must stay selected: \(title)")
            XCTAssertEqual(picker.buttons.allElementsBoundByIndex.filter(\.isSelected).map(\.label), [title])
        }
    }
}
