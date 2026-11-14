import XCTest

@MainActor
final class DashboardRangePickerTests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testRangePickerFollowsTabPlacementAcrossRotation() {
        checkRangePicker(language: "zh-Hans", contentSize: "UICTContentSizeCategoryL", all: "全部")
    }

    func testRangePickerRemainsReachableAtLargestTextSize() {
        checkRangePicker(language: "en", contentSize: "UICTContentSizeCategoryAccessibilityXXXL", all: "All")
    }

    private func checkRangePicker(language: String, contentSize: String, all: String) {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = [
            "-UITestMode", "-DashboardScenario", "long",
            "-AppleLanguages", "(\(language))", "-AppleLocale", language == "en" ? "en_US" : "zh_CN",
            "-UIPreferredContentSizeCategoryName", contentSize
        ]
        app.launch()
        defer {
            app.terminate()
            XCUIDevice.shared.orientation = .portrait
        }
        XCTAssertTrue(app.descendants(matching: .any)
            .matching(identifier: "screenshot.ready.home").firstMatch.waitForExistence(timeout: 20))

        checkPlacement(in: app)
        let summary = app.descendants(matching: .any).matching(identifier: "dashboard.card.analysisCount").firstMatch
        let originalSummary = summary.label
        let allButton = app.segmentedControls.firstMatch.buttons[all]
        allButton.tap()
        XCTAssertTrue(allButton.isSelected)
        XCTAssertNotEqual(summary.label, originalSummary, "Changing the range must update the dashboard data")
        screenshot("range-portrait-\(language)", in: app)

        XCUIDevice.shared.orientation = .landscapeLeft
        checkPlacement(in: app)
        XCTAssertTrue(app.segmentedControls.firstMatch.buttons[all].isSelected,
                      "A layout change must preserve the selected date range")
        screenshot("range-landscape-\(language)", in: app)

        XCUIDevice.shared.orientation = .portrait
        checkPlacement(in: app)
        XCTAssertTrue(app.segmentedControls.firstMatch.buttons[all].isSelected)
        XCTAssertEqual(app.alerts.count, 0)
    }

    private func checkPlacement(in app: XCUIApplication) {
        let picker = app.segmentedControls.firstMatch
        waitUntilHittable(picker)
        XCTAssertEqual(app.segmentedControls.count, 1, "Show exactly one date range picker")
        XCTAssertEqual(picker.buttons.count, 4)
        for button in picker.buttons.allElementsBoundByIndex where !button.isSelected {
            waitUntilHittable(button)
        }

        let tabBar = app.tabBars.firstMatch
        // Side tabs are not exposed as a TabBar by XCTest.
        let bottomTabs = tabBar.exists && tabBar.frame.width > tabBar.frame.height && tabBar.frame.midY > app.frame.midY
        if bottomTabs {
            XCTAssertGreaterThan(picker.frame.minY, app.frame.midY)
            XCTAssertLessThanOrEqual(picker.frame.maxY, tabBar.frame.minY)
        } else {
            let summary = app.descendants(matching: .any).matching(identifier: "dashboard.card.analysisCount").firstMatch
            XCTAssertLessThanOrEqual(picker.frame.maxY, summary.frame.minY,
                                    "Top or side tabs must not leave a floating picker over the cards")
        }
        XCTAssertTrue(app.frame.contains(picker.frame), "The whole picker must stay within the app")
    }

    private func waitUntilHittable(_ element: XCUIElement) {
        let ready = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == true AND hittable == true"), object: element
        )
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 10), .completed)
    }

    private func screenshot(_ name: String, in app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
