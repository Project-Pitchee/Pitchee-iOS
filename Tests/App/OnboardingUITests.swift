import XCTest

@MainActor
final class OnboardingUITests: XCTestCase {
    func testSelectionNavigationAndCompletionPersist() {
        continueAfterFailure = false
        let app = XCUIApplication(bundleIdentifier: "com.lvyzhan.Pitchee")
        // Run on an isolated simulator with onboarding.progress.completedVersion reset to 0.
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()

        let next = app.buttons["onboarding.continue"]
        let back = app.buttons["onboarding.back"]
        let feminine = app.buttons["onboarding.voice.feminine"]
        let masculine = app.buttons["onboarding.voice.masculine"]
        let undecided = app.buttons["onboarding.voice.undecided"]

        waitUntilHittable(next)
        XCTAssertFalse(back.exists)
        screenshot("welcome", in: app)
        next.tap()

        waitUntilHittable(back)
        XCTAssertFalse(feminine.exists)
        screenshot("privacy", in: app)
        next.tap()

        XCTAssertTrue(feminine.waitForExistence(timeout: 5))
        XCTAssertFalse(next.isEnabled, "Finishing requires an explicit voice preference")
        screenshot("preferences without a selection", in: app)
        for option in [feminine, masculine, undecided] {
            reveal(option, in: app)
            option.tap()
            XCTAssertTrue(option.isSelected)
            XCTAssertTrue(next.isEnabled)
        }
        reveal(feminine, in: app)
        feminine.tap()
        back.tap()
        XCTAssertFalse(feminine.exists)
        next.tap()
        XCTAssertTrue(feminine.waitForExistence(timeout: 5))
        XCTAssertTrue(feminine.isSelected, "Going back must retain the selected preference")
        screenshot("preferences with retained selection", in: app)
        next.tap()
        waitForMain(in: app)

        app.terminate()
        app.launch()
        waitForMain(in: app)
        XCTAssertFalse(next.exists, "Relaunching after completion must skip onboarding")

        app.terminate()
        // This screenshot-only override is not used when verifying completion persistence.
        app.launchArguments += [
            "-onboarding.progress.completedVersion", "0",
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"
        ]
        app.launch()
        waitUntilHittable(next)
        screenshot("welcome at largest dynamic type", in: app)
        next.tap()
        waitUntilHittable(back)
        screenshot("privacy at largest dynamic type", in: app)
        next.tap()
        XCTAssertTrue(feminine.waitForExistence(timeout: 5))
        screenshot("preferences at largest dynamic type", in: app)
        reveal(undecided, in: app)
        undecided.tap()
        XCTAssertTrue(undecided.isSelected)
        XCTAssertTrue(next.isHittable, "The primary action remains reachable at the largest text size")
        screenshot("scrolled preferences at largest dynamic type", in: app)
        app.terminate()
        app.launchArguments = []
    }

    private func waitUntilHittable(_ element: XCUIElement) {
        let ready = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == true AND hittable == true"),
            object: element
        )
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 10), .completed)
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<6 where !element.isHittable {
            if element.frame.maxY < app.frame.midY {
                app.swipeDown()
            } else {
                app.swipeUp()
            }
        }
        XCTAssertTrue(element.isHittable, "The preference must be reachable by scrolling")
    }

    private func waitForMain(in app: XCUIApplication) {
        let visible = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in
                app.tabBars.firstMatch.exists || app.buttons["tab.trends"].exists
            }, object: nil
        )
        XCTAssertEqual(XCTWaiter.wait(for: [visible], timeout: 10), .completed)
    }

    private func screenshot(_ name: String, in app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
