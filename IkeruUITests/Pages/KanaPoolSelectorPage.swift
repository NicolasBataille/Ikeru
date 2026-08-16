import XCTest

/// Page object for `KanaPoolSelectorView` — GAP-01 two-client merge test
/// only. Scoped to exactly what that test needs: select the `hVowels` group
/// (5 characters — the smallest group in `KanaGroup`, chosen so the whole
/// pool can be answered card-by-card in one phase) and launch free
/// practice, which — unlike "Review Due" — never depends on `dueDate`, so
/// it's reachable immediately after a fresh group selection with no wait on
/// scheduling state.
struct KanaPoolSelectorPage {
    let app: XCUIApplication

    private var explainerDismissButton: XCUIElement {
        app.buttons["kanaPool.explainerDismiss"]
    }

    private var vowelsGroupCard: XCUIElement {
        app.buttons["kanaPool.group.hVowels"]
    }

    private var freePracticeButton: XCUIElement {
        app.buttons["kanaPool.drill.freePractice"]
    }

    /// Dismisses the one-time Sakura "drill modes" explainer if it's
    /// showing — only appears on a brand-new profile's FIRST visit to this
    /// screen. A no-op (immediately returns) if it never appears within the
    /// short timeout, so callers can invoke this unconditionally.
    func dismissExplainerIfPresent(timeout: TimeInterval = 3) {
        guard explainerDismissButton.waitForExistence(timeout: timeout) else { return }
        explainerDismissButton.tap()
    }

    @discardableResult
    func waitForVowelsGroup(timeout: TimeInterval = 10) -> Bool {
        vowelsGroupCard.waitForExistence(timeout: timeout)
    }

    func selectVowelsGroup() {
        vowelsGroupCard.tap()
    }

    /// `.disabled(vm.selectedGroups.isEmpty)` on `freePracticeButton`
    /// (`KanaPoolSelectorView.drillButton`) means it can exist but not be
    /// hittable for a brief moment right after `selectVowelsGroup()`'s tap
    /// animation starts — waits on `isEnabled` via a predicate expectation
    /// rather than a fixed sleep, same reasoning `KanaQuizPage
    /// .answerCurrentCard` documents for its own "Submit" → "Next" wait.
    func tapFreePractice(testCase: XCTestCase) {
        let becomesEnabled = testCase.expectation(
            for: NSPredicate(format: "isEnabled == true"),
            evaluatedWith: freePracticeButton
        )
        testCase.wait(for: [becomesEnabled], timeout: 10)
        freePracticeButton.tap()
    }
}
