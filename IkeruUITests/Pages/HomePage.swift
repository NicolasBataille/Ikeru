import XCTest

/// Page object for the Home (Practice) tab / dashboard.
struct HomePage {
    let app: XCUIApplication

    /// The "稽古を始める · BEGIN PRACTICE" hero CTA — only rendered once
    /// `HomeViewModel` has composed a non-empty session (see
    /// `HomeView.proverbHero`), so its presence is itself a signal that the
    /// dashboard finished loading fixture data, not just that some view
    /// rendered.
    var beginPracticeButton: XCUIElement {
        app.buttons["home.beginPracticeButton"]
    }

    /// "かな X/92 learned" count — unlike the CTA above, this renders
    /// unconditionally once `HomeViewModel` has data (see
    /// `HomeView.kanaProgressLine`), so it's the more reliable of the two
    /// signals when a test doesn't care whether a session is composable.
    var kanaProgressCount: XCUIElement {
        app.staticTexts["home.kanaProgressCount"]
    }

    @discardableResult
    func waitForDashboardData(timeout: TimeInterval = 10) -> Bool {
        kanaProgressCount.waitForExistence(timeout: timeout)
    }

    @discardableResult
    func waitForBeginPracticeButton(timeout: TimeInterval = 10) -> Bool {
        beginPracticeButton.waitForExistence(timeout: timeout)
    }

    func tapBeginPractice() {
        beginPracticeButton.tap()
    }
}
