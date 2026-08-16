import XCTest

/// Page object for `KanaQuizView` — the 4-choice romaji recognition quiz
/// exercise reached from an active session.
///
/// Deliberately picks ANY option rather than the correct one: this suite
/// tests that the exercise flow (see an option, answer it, advance) works
/// end-to-end, not the grading logic itself, which
/// `KanaDrillViewModelTests` (IkeruTests, unit-level) already covers. All
/// four option buttons share one identifier (`kanaQuiz.optionButton` — see
/// `KanaQuizView.optionButton`'s doc comment) for exactly this reason.
struct KanaQuizPage {
    let app: XCUIApplication

    private var optionButtons: XCUIElementQuery {
        app.buttons.matching(identifier: "kanaQuiz.optionButton")
    }

    private var actionButton: XCUIElement {
        app.buttons["kanaQuiz.actionButton"]
    }

    @discardableResult
    func waitForOptions(timeout: TimeInterval = 10) -> Bool {
        optionButtons.firstMatch.waitForExistence(timeout: timeout)
    }

    /// Selects the first available option, then taps the action button
    /// twice: once to submit (label reads "Submit"), once to advance to the
    /// next card (label reads "Next" — see `KanaQuizView.actionButton`).
    ///
    /// `submitQuizAnswer()` runs in a `Task` (grading + persistence are
    /// async), so the label flip from "Submit" to "Next" is not immediate —
    /// tapping again right away risks re-firing the still-"Submit" button
    /// instead of advancing. Waits on the label via a predicate expectation
    /// rather than a fixed sleep, matching the same reasoning CLAUDE.md
    /// documents for measuring over inferring.
    func answerCurrentCard(testCase: XCTestCase) {
        optionButtons.firstMatch.tap()
        actionButton.tap() // Submit
        let becomesNext = testCase.expectation(
            for: NSPredicate(format: "label == %@", "Next"),
            evaluatedWith: actionButton
        )
        testCase.wait(for: [becomesNext], timeout: 10)
        actionButton.tap() // Next
    }
}
