import XCTest

@MainActor
final class DashboardCardNavigationTests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testSummaryCardsStayOnDashboardAndMetricDetailsStillOpen() {
        checkCardNavigation(contentSize: "UICTContentSizeCategoryL", screenshotSuffix: "standard")
    }

    func testSummaryCardsAndMetricCloseAtLargestTextSize() {
        checkCardNavigation(
            contentSize: "UICTContentSizeCategoryAccessibilityXXXL",
            screenshotSuffix: "largest-text"
        )
    }

    private func checkCardNavigation(contentSize: String, screenshotSuffix: String) {
        let app = XCUIApplication()
        app.launchArguments = [
            "-UITestMode", "-DashboardScenario", "few",
            "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN",
            "-UIPreferredContentSizeCategoryName", contentSize
        ]
        app.launch()
        defer { app.terminate() }
        XCTAssertTrue(app.descendants(matching: .any)
            .matching(identifier: "screenshot.ready.home").firstMatch.waitForExistence(timeout: 20))

        let close = app.buttons["dashboard.detail.close"]
        for component in ["analysisCount", "openedDays"] {
            let identifier = "dashboard.card.\(component)"
            let summary = app.descendants(matching: .any).matching(identifier: identifier).firstMatch
            waitUntilHittable(summary)
            XCTAssertFalse(app.buttons[identifier].exists, "Summary cards must not expose a button action")
            XCTAssertFalse(summary.label.isEmpty, "Summary readings must remain accessible")
            summary.tap()
            let opened = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == true"), object: close)
            opened.isInverted = true
            XCTAssertEqual(XCTWaiter.wait(for: [opened], timeout: 1), .completed,
                           "Tapping a summary card must stay on the dashboard")
            XCTAssertTrue(app.navigationBars["Pitchee"].isHittable)
        }
        screenshot("summary-cards-\(screenshotSuffix)", in: app)

        let card = app.buttons["dashboard.card.compositeScore"]
        for _ in 0..<6 where !card.isHittable { app.swipeUp() }
        waitUntilHittable(card)
        card.tap()
        waitUntilHittable(close)
        XCTAssertEqual(close.frame.width, 44, accuracy: 1)
        XCTAssertEqual(close.frame.height, 44, accuracy: 1)
        screenshot("metric-card-\(screenshotSuffix)", in: app)
        close.tap()
        waitUntilHittable(card)
        XCTAssertFalse(close.exists)
        XCTAssertEqual(app.alerts.count, 0, "The fixture must never request microphone access")
    }

    private func waitUntilHittable(_ element: XCUIElement) {
        let ready = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == true AND hittable == true AND enabled == true"), object: element
        )
        let result = XCTWaiter.wait(for: [ready], timeout: 10)
        if result != .completed {
            let app = XCUIApplication()
            screenshot("dashboard-navigation-failure", in: app)
            let hierarchy = XCTAttachment(string: app.debugDescription)
            hierarchy.name = "dashboard-navigation-hierarchy"
            hierarchy.lifetime = .keepAlways
            add(hierarchy)
        }
        XCTAssertEqual(result, .completed)
    }

    private func screenshot(_ name: String, in app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
