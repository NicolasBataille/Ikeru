import XCTest

/// Two questions, one file: what happens when a learner has nothing due, and
/// what happens when they do.
///
/// ## This suite was red from the day it shipped, and its own diagnosis was wrong
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
///    still-open problem noted on the two test methods it affects.)
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
/// ## And the fixture the caught-up tests needed
///
/// The two caught-up tests below spent a day red on a premise nobody had
/// measured: that `-mockDue=0` produces a profile with nothing to review. It
/// does not — `mockDue` governs only the content cards, while `seedKana` seeds
/// its own 92 characters from `mockLevel`, including a fixed 10-card overdue
/// band at *every* level. They now use `-mockNothingDue`, which exists for
/// exactly this and is proved at unit level by `TestFixturesNothingDueTests`.
///
/// The behaviour itself was never in doubt: `AdaptiveSessionViewModelTests`
/// covers it with cards it controls directly instead of through the fixture.
///
/// The lesson worth keeping: "session never reached a kana quiz option" was a
/// true statement that named the wrong cause, and rounds of reasoning built on
/// it — including two of mine.
final class SessionAnswerFlowUITests: IkeruUITestCase {

    /// Nothing due must produce a PROPOSAL, not silence.
    ///
    /// It fails if the app goes back to doing nothing on `-autoStartSession`
    /// with an empty queue — exactly the regression that would otherwise be
    /// invisible, because "nothing happened" looks identical to "still
    /// loading" from the outside.
    func testNothingDueOffersAProposalInsteadOfSilence() {
        let app = launch([
            LaunchArguments.mockProfile,
            LaunchArguments.skipTour,
            LaunchArguments.skipHints,
            LaunchArguments.mockLevel(30),
            LaunchArguments.mockNothingDue,
            LaunchArguments.autoStartSession,
            LaunchArguments.startTab(1), // Practice/Home
        ])

        let proposal = app.otherElements["home.caughtUpProposal"]
        // 30s, not the usual 15–20: `-mockNothingDue` is the heaviest fixture
        // in the suite — all 92 kana replayed through FSRS with a full review
        // history each — and this test runs first, so it eats the cold
        // first-launch cost of a freshly installed binary. Observed timing out
        // at 20s on exactly that combination while passing twice in isolation.
        // The assertion is unchanged; only the patience is.
        XCTAssertTrue(
            proposal.waitForExistence(timeout: 30),
            "Nothing was due and the app showed no caught-up proposal — the "
                + "learner is back in front of a dead end"
        )

        // At least one offer must be actionable. Assert on the pair rather
        // than on a specific offer: the contract is "something is offered".
        //
        // Under `-mockNothingDue` it will be **deepen** — and the two are
        // mutually exclusive there, not by accident. Discover draws from
        // never-reviewed cards, and a card nobody has reviewed is itself due,
        // so it cannot exist in a pool with nothing due. Measured, and pinned
        // by `TestFixturesNothingDueTests`.
        let deepen = app.buttons["home.caughtUp.deepen"]
        let discover = app.buttons["home.caughtUp.discover"]
        XCTAssertTrue(
            deepen.waitForExistence(timeout: 5) || discover.waitForExistence(timeout: 5),
            "The proposal appeared but offered nothing to do"
        )
    }

    /// Tapping an offer must actually start a session.
    ///
    /// The offer buttons are only rendered when their pool can produce one
    /// (`caughtUpAvailability`), so a button that appears and then does
    /// nothing is a real defect — the same class this whole change removes,
    /// one layer up.
    ///
    /// ⚠️ Expected to fail on GAP-18 while that stays open: a session composes
    /// under XCUITest but its full-screen cover never presents. That is not a
    /// defect in the caught-up offer — the same failure hits the ordinary path
    /// below, and both work under `simctl launch`.
    func testTappingAnOfferStartsASession() {
        let app = launch([
            LaunchArguments.mockProfile,
            LaunchArguments.skipTour,
            LaunchArguments.skipHints,
            LaunchArguments.mockLevel(30),
            LaunchArguments.mockNothingDue,
            LaunchArguments.startTab(1),
        ])

        let deepen = app.buttons["home.caughtUp.deepen"]
        let discover = app.buttons["home.caughtUp.discover"]

        let offer: XCUIElement
        if deepen.waitForExistence(timeout: 20) {
            offer = deepen
        } else if discover.waitForExistence(timeout: 5) {
            offer = discover
        } else {
            XCTFail("No caught-up offer was available to tap")
            return
        }

        offer.tap()

        let session = SessionPage(app: app)
        XCTAssertTrue(
            session.waitForCard(timeout: 15),
            "Tapping a caught-up offer did not lead to an exercise — the "
                + "button looked live and did nothing"
        )
        XCTAssertEqual(app.state, .runningForeground)
    }

    /// The ordinary path: with cards due, tapping BEGIN PRACTICE opens a
    /// session, and answering one card queues the next.
    ///
    /// Drives the CTA rather than `-autoStartSession` because it is the
    /// gesture a learner actually makes — but note that swapping one for the
    /// other did NOT fix this test, and what remains is an open question.
    ///
    /// ⚠️ STILL RED (GAP-18). Measured 2026-08-16, once the launch arguments
    /// were confirmed arriving, and stated only as far as the measurement goes:
    ///
    /// - Under XCUITest the session **composes**. `Logger.ui` records
    ///   "session.vocabPool level=n5 count=693", "Live Activity started" and
    ///   "Session started via SessionPlanner: 20 exercises (20 SRS)".
    /// - The full-screen cover nonetheless **never appears** — confirmed twice
    ///   over, by the accessibility dump and by a simulator screenshot taken
    ///   mid-run, both showing Home.
    /// - It fails the same way from `-autoStartSession` and from a CTA tap
    ///   several seconds after "Home screen data loaded". So it is **not** a
    ///   launch-timing race.
    /// - The same flags under `xcrun simctl launch` present the session
    ///   normally. So it is XCUITest-correlated.
    ///
    /// The mechanism is NOT identified. An earlier draft asserted "UIKit drops
    /// a presentation requested that early" and inferred a Siri-shortcut risk
    /// for real learners; both were falsified by the two bullets above before
    /// shipping. Do not re-derive them — measure.
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
