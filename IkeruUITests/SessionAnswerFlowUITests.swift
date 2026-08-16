import XCTest

/// Starts a session and answers one exercise — the core "does the learning
/// loop actually work end-to-end" smoke test that GAP-09 names as missing.
///
/// ## This test was red from the day it shipped, and its own diagnosis was wrong
///
/// It shipped deliberately red in PR #106 with two named suspects: a first-run
/// overlay hijacking navigation, or "the composed session's first exercise not
/// actually being the plain kana quiz this file's header comment predicts".
/// Adding `skipTour` didn't fix it, and the file recorded that as evidence
/// against the overlay theory. Both readings were partly right and both stopped
/// one step short.
///
/// Measured 2026-08-16, by launching the app with these exact arguments and
/// photographing the screen instead of re-reading the assertion:
///
/// 1. **The session started and was showing a card** — under `simctl launch`,
///    with these exact arguments. The learning loop itself was never broken.
///    (Under XCUITest it composes but does not present; that is the separate,
///    still-open problem on the test method below.)
/// 2. **`kanaQuiz.optionButton` cannot appear in a session, at any setting.**
///    `KanaQuizView` is instantiated in exactly one place — `KanaDrillModeSelector`,
///    the kana drill under Explore. A session renders `.srsReview` items as
///    swipeable flashcards (`SRSCardView` + `GradeButtonsView`), a surface that
///    carried no accessibility identifiers at all. The test was waiting on a
///    screen the session has no route to.
/// 3. **A second overlay was covering the card anyway.** `SwipeTutorialView`
///    fires on the first card of a first session and hides it, and its grade
///    buttons, behind a "Got it" scrim. `skipTour` doesn't touch it — that flag
///    owns the *tab tour*. Hence `-skipHints`.
///
/// A fourth explanation was investigated at length and **is false**: that
/// XCUITest launch arguments never reach the app. See `AppEnvironment` for the
/// measurement that killed it. Do not revive it — flags arrive fine.
///
/// The lesson worth keeping: "session never reached a kana quiz option" was a
/// true statement that named the wrong cause, and rounds of reasoning built on
/// it — including two of mine. One screenshot settled points 1 and 3; one run
/// against `dev` settled the fourth.
///
/// Now driven through `SessionPage`, against the surface a session actually
/// shows.
final class SessionAnswerFlowUITests: IkeruUITestCase {

    /// The ordinary path: with cards due, tapping BEGIN PRACTICE opens a
    /// session, and answering one card queues the next.
    ///
    /// Drives the CTA rather than `-autoStartSession` because it is the
    /// gesture a learner actually makes — but note that swapping one for the
    /// other did NOT fix this test, and what remains is an open question, not
    /// a solved one.
    ///
    /// ⚠️ STILL RED. Measured 2026-08-16, once the launch arguments were
    /// actually arriving (see `AppEnvironment`), and stated only as far as the
    /// measurement goes:
    ///
    /// - Under XCUITest the session **composes**. `Logger.ui` records
    ///   "session.vocabPool level=n5 count=693", "Live Activity started" and
    ///   "Session started via SessionPlanner: 20 exercises (20 SRS)".
    /// - The full-screen cover nonetheless **never appears** — confirmed twice
    ///   over, by the accessibility dump and by a simulator screenshot taken
    ///   mid-run, both showing Home.
    /// - It fails the same way from `-autoStartSession` (fired in Home's
    ///   `.task`) and from a CTA tap several seconds after "Home screen data
    ///   loaded". So it is **not** a launch-timing race.
    /// - The same flags under `xcrun simctl launch` present the session
    ///   normally. So it is XCUITest-correlated.
    ///
    /// The mechanism is NOT identified. An earlier draft of this comment
    /// asserted "UIKit drops a presentation requested that early" and inferred
    /// a Siri-shortcut risk for real learners; both were falsified by the two
    /// bullets above before shipping. Do not re-derive them — measure.
    ///
    /// Not chased further here on purpose: the fix, if it is in the app,
    /// would land in `HomeView`'s presentation site, which PR #111 is
    /// currently rewriting.
    ///
    /// The rest of the harness this red depends on is fixed and proven — see
    /// the file header.
    func testStartSessionAndAnswerOneExercise() {
        let app = launch([
            LaunchArguments.mockProfile,
            LaunchArguments.skipTour,
            LaunchArguments.skipHints,
            LaunchArguments.mockLevel(30),
            LaunchArguments.mockDue(10),
            LaunchArguments.mockMastered(0),
            LaunchArguments.startTab(1), // Practice/Home
        ])

        let beginPractice = app.buttons["home.beginPracticeButton"]
        XCTAssertTrue(
            beginPractice.waitForExistence(timeout: 20),
            "Home never offered BEGIN PRACTICE with 10 cards due"
        )
        beginPractice.tap()

        let session = SessionPage(app: app)
        XCTAssertTrue(
            session.waitForCard(timeout: 15),
            "Tapping BEGIN PRACTICE did not open a session card"
        )

        session.answerCurrentCard(testCase: self)

        // With cards still queued behind this one, one answer never ends the
        // session, so the strong assertion is that another card arrives — not
        // just "the app is still running", which would also be true of a
        // silent crash-to-background.
        XCTAssertTrue(
            session.waitForCard(timeout: 10),
            "No next card appeared after answering — the session may have stalled"
        )
        XCTAssertEqual(
            app.state, .runningForeground,
            "App left the foreground after answering an exercise"
        )
    }
}
