import XCTest

@MainActor
final class PitcheeScreenshots: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testScreenshots() throws {
        let language = Locale.preferredLanguages.first ?? "en"
        let screens = ["home", "monitor", "insights", "articles", "history"]
        for (index, screen) in screens.enumerated() {
            let app = XCUIApplication()
            app.launchArguments = [
                "-UITestMode", "-ScreenshotScreen", screen,
                "-AppleLanguages", "(\(language))", "-AppleLocale", Locale.current.identifier,
                "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryL"
            ]
            app.launch()
            XCTAssertTrue(app.wait(for: .runningForeground, timeout: 15))
            let ready = app.descendants(matching: .any)
                .matching(identifier: "screenshot.ready.\(screen)").firstMatch
            XCTAssertTrue(ready.waitForExistence(timeout: 20), "Bundled fixtures must finish loading")
            XCTAssertEqual(app.alerts.count, 0, "Screenshot mode must not request microphone permission")
            switch screen {
            case "home": XCTAssertTrue(app.buttons["practice.openScoring"].exists)
            case "monitor": XCTAssertTrue(app.descendants(matching: .any)["monitor.frequency"].exists)
            case "articles": XCTAssertTrue(app.buttons["voiceLibrary.categoryFilter"].exists)
            case "history": XCTAssertGreaterThan(app.buttons.count, 3, "Seeded history must contain recording links")
            default: XCTAssertTrue(app.scrollViews.firstMatch.exists, "Result must render its content")
            }
            let attachment = XCTAttachment(screenshot: app.screenshot())
            attachment.name = String(format: "%02d-%@", index + 1, screen)
            attachment.lifetime = .keepAlways
            add(attachment)
            app.terminate()
        }
    }
}

/// Kept outside PitcheeScreenshots so the five-screen export does not rerun it.
@MainActor
final class PitcheeAboutTests: XCTestCase {
    func testAboutShowsBuiltMarketingVersionAndBuildNumber() throws {
        continueAfterFailure = false
        // All app/test targets inherit the project's version fields. The test
        // artifact is the independent expected value, not a version constant.
        let info = try XCTUnwrap(Bundle(for: PitcheeAboutTests.self).infoDictionary)
        let marketing = try XCTUnwrap(info["CFBundleShortVersionString"] as? String)
        let build = try XCTUnwrap(info["CFBundleVersion"] as? String)
        XCTAssertFalse(marketing.isEmpty)
        XCTAssertFalse(build.isEmpty)

        let app = XCUIApplication()
        app.launchArguments = [
            "-UITestMode", "-ScreenshotScreen", "home",
            "-AppleLanguages", "(en)", "-AppleLocale", "en_US"
        ]
        app.launch()
        defer { app.terminate() }
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "screenshot.ready.home").firstMatch
            .waitForExistence(timeout: 20))
        let legacyAbout = app.buttons["tab.about"]
        let about = legacyAbout.exists ? legacyAbout : app.tabBars.buttons["About"]
        XCTAssertTrue(about.waitForExistence(timeout: 5))
        about.tap()
        let version = app.descendants(matching: .any).matching(identifier: "about.app.version").firstMatch
        XCTAssertTrue(version.waitForExistence(timeout: 10))
        XCTAssertEqual(version.value as? String, "\(marketing) (\(build))")
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "about-app-version"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
