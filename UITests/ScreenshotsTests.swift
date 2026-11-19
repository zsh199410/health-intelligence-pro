import XCTest

/// Screenshot gate for Issue #1 (7/7 visual acceptance).
/// Seven pages x three display modes = 21 screenshots:
/// welcome, today, settings, sleep, heart, records, report
/// each in light, dark and extra-large text.
/// The simulator has no HealthKit data, so every page shows its honest
/// empty state ("—" / "暂无记录"); no sample data is ever manufactured.
/// Screenshots are XCTAttachments (lifetime .keepAlways) so they land in
/// the .xcresult bundle; CI exports them as plain PNGs.
/// The test also taps through the real navigation (skip onboarding, open
/// Settings, open a metric detail page and go back) so a dead button or
/// a broken push fails the run instead of silently screenshotting.
final class ScreenshotsTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    func testLightScreenshots() {
        launch(light: true, largeText: false)
        captureAllPages(prefix: "light")
    }

    func testDarkScreenshots() {
        launch(light: false, largeText: false)
        captureAllPages(prefix: "dark")
    }

    func testLargeTextScreenshots() {
        launch(light: true, largeText: true)
        captureAllPages(prefix: "large-text")
    }

    private func launch(light: Bool, largeText: Bool) {
        app = XCUIApplication()
        // Force the app process into light/dark via launch argument.
        // XCUIDevice.shared.appearance is an async simulator-level change
        // that did not reach the app in CI (#43/#48: dark and large-text
        // shots were pixel-identical to light, 0.05%/0.03% diff).
        // -AppleInterfaceStyle is applied at process launch, deterministic.
        app.launchArguments += ["-AppleInterfaceStyle", light ? "Light" : "Dark"]
        // Reset onboarding so every mode starts at the welcome screen.
        app.launchArguments += ["-resetOnboardingForScreenshots"]
        if largeText {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName",
                                    "UICTContentSizeCategoryAccessibilityExtraLarge"]
        }
        app.launch()
    }

    private func captureAllPages(prefix: String) {
        // 1/7 welcome (first-launch screen).
        XCTAssertTrue(app.staticTexts["读懂健康，从真实数据开始"].waitForExistence(timeout: 10))
        capture("welcome", prefix: prefix)
        app.buttons["跳过"].tap()

        // 2/7 today.
        XCTAssertTrue(app.staticTexts["今日"].waitForExistence(timeout: 10))
        capture("today", prefix: prefix)

        // 3/7 settings (gear on Today, dismissed with 完成).
        app.buttons["设置与隐私"].tap()
        XCTAssertTrue(app.staticTexts["设置与隐私"].waitForExistence(timeout: 10))
        capture("settings", prefix: prefix)
        app.buttons["完成"].tap()
        XCTAssertTrue(app.staticTexts["今日"].waitForExistence(timeout: 10))

        // 4/7 sleep.
        tapTab("睡眠")
        XCTAssertTrue(app.staticTexts["睡眠"].waitForExistence(timeout: 10))
        capture("sleep", prefix: prefix)

        // 5/7 heart.
        tapTab("心脏")
        XCTAssertTrue(app.staticTexts["心脏健康"].waitForExistence(timeout: 10))
        capture("heart", prefix: prefix)

        // 6/7 records. The page is a List: rows below the fold (such as
        // "暂无笔记" at the bottom) are not in the accessibility tree
        // until scrolled to, so assert on the top of the page instead —
        // the navigation title and the first section's button.
        tapTab("健康库")
        XCTAssertTrue(app.staticTexts["健康数据库"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["录入血压、血糖或体重"].waitForExistence(timeout: 10))
        capture("records", prefix: prefix)

        // 7/7 report.
        tapTab("报告")
        XCTAssertTrue(app.staticTexts["把每一次记录，变成更清晰的理解"].waitForExistence(timeout: 10))
        capture("report", prefix: prefix)

        // Button-tap evidence: back on Today, open Settings and return.
        // The assertions are the proof (no extra screenshot).
        // NOTE (#61 root cause): the metric tile CANNOT exist in the
        // simulator. TodayView.stateContent only renders
        // modulesSection/vitalsSection/insightsSection in its final
        // else branch, which requires hasNoData == false — and the
        // simulator has no HealthKit data, so readings are empty and
        // the page shows the permission card / empty state instead.
        // Six straight CI failures (#55–#61) proved this: no hierarchy
        // snapshot ever contained "核心生命体征", no scroll method
        // (app.swipeUp, scrollView.swipeUp, coordinate drag) could
        // reach a section that is never built, and the eager-grid
        // change did not help because the whole section is gated.
        // Tile navigation is verified on a real device (which has real
        // HealthKit data), not here. In the simulator, prove the app
        // is interactive by opening Settings from the toolbar and
        // returning.
        tapTab("今日")
        XCTAssertTrue(app.staticTexts["今日"].waitForExistence(timeout: 10))
        let settingsButton = app.buttons["设置与隐私"]
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 10), "settings button missing")
        settingsButton.tap()
        XCTAssertTrue(app.staticTexts["设置与隐私"].waitForExistence(timeout: 10), "settings sheet missing")
        app.buttons["完成"].tap()
        XCTAssertTrue(app.staticTexts["今日"].waitForExistence(timeout: 10))
    }

    private func tapTab(_ label: String) {
        // In large-text mode a tap can miss the tab bar item and leave
        // the previous tab selected (#62: 健康库 never switched, the
        // page stayed on 心脏 while "健康数据库" timed out), so retry
        // the tap until the tab reports selected. Tapping an
        // already-selected tab is a no-op, so extra taps are harmless;
        // the caller's content assertion still decides the outcome if
        // the switch never lands.
        for _ in 0..<3 {
            let tab = app.buttons[label]
            XCTAssertTrue(tab.waitForExistence(timeout: 10), "tab \(label) missing")
            tab.tap()
            Thread.sleep(forTimeInterval: 1)
            if app.buttons[label].isSelected {
                return
            }
        }
    }

    private func capture(_ page: String, prefix: String) {
        Thread.sleep(forTimeInterval: 1)
        // Full device screen, not just the app window: the visual gate
        // needs the true complete screen (status bar included). An
        // app.screenshot() capture came back 960x1440 on CI — not the
        // iPhone 17 Pro full screen (1206x2622) — with a black top area
        // and content clipped at the right edge, so it cannot stand as
        // 7/7 evidence. XCUIScreen captures the whole screen buffer.
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "\(prefix)-\(page)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
