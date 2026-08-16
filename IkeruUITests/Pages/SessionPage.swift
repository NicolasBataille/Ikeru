import XCTest

/// Page object for a live session — `ActiveSessionView` driving
/// `SRSCardView` + `GradeButtonsView`.
///
/// ## Why this exists, and what it replaces
///
/// `KanaQuizPage` was standing in for this, and could never work. Measured
/// 2026-08-16: `kanaQuiz.optionButton` belongs to `KanaQuizView`, which is
/// instantiated in exactly one place — `KanaDrillModeSelector`, the kana
/// drill under Explore. A session renders its `.srsReview` items as swipeable
/// flashcards instead, on a surface that carried **no accessibility
/// identifiers at all**. So `testStartSessionAndAnswerOneExercise` was
/// waiting for a screen that no session can reach, and the failure it
/// reported ("session never reached a kana quiz option") described the
/// symptom while naming the wrong cause: the session had started, was showing
/// a card, and was working.
///
/// ## The two-step answer
///
/// A session card is answered in two beats, not one: tap the card to flip it
/// (`SRSCardView`'s `onTapGesture` toggling `isRevealed`), *then* pick one of
/// the four FSRS grades, which only exist once revealed
/// (`ExerciseTransitionContainer` gates `GradeButtonsView` on `isRevealed`).
/// Swiping the card grades it too, but tapping a named grade button is what
/// lets a test say which grade it meant.
///
/// ## Presentation cards are waited through, not driven
///
/// A session that introduces a never-reviewed kana shows an ungraded
/// `NewCardPresentationView` first (`NewCardPresentationScheduler`), which has
/// no card and no grade buttons. `waitForCard` simply waits for
/// `session.card`, so it rides through that phase instead of racing it —
/// nothing here needs to know whether the intro ran.
struct SessionPage {
    let app: XCUIApplication

    /// The interactive front of the deck. Peek layers behind it are
    /// non-hit-testable decoration and carry no identifier.
    private var card: XCUIElement {
        app.otherElements["session.card"]
    }

    private func gradeButton(_ grade: String) -> XCUIElement {
        app.buttons["session.gradeButton.\(grade)"]
    }

    @discardableResult
    func waitForCard(timeout: TimeInterval = 15) -> Bool {
        card.waitForExistence(timeout: timeout)
    }

    /// Reveals the current card and grades it `good`.
    ///
    /// `good` rather than `again`: `again` reschedules the same card within
    /// the session, so a test asserting "another card is queued after this
    /// one" could be satisfied by the card it just answered coming straight
    /// back — which would prove nothing about the queue advancing.
    ///
    /// Asserts on the reveal rather than tapping blind: if the grade row
    /// never appears, the defect is the flip, and a bare `tap()` on a
    /// non-existent button would report it as a generic XCUITest failure
    /// several lines later.
    func answerCurrentCard(testCase: XCTestCase, grade: String = "good") {
        card.tap()
        let good = gradeButton(grade)
        XCTAssertTrue(
            good.waitForExistence(timeout: 10),
            "Tapping the card did not reveal the grade buttons — the card "
                + "never flipped"
        )
        good.tap()
    }
}
