import XCTest

/// Starts a session and answers one exercise — the core "does the learning
/// loop actually work end-to-end" smoke test that GAP-09 names as missing.
///
/// Fixture composition is deliberately narrow (`mockLevel=30`, `mockDue=0`,
/// `mockMastered=0`) so the FIRST composed session is guaranteed to be a
/// plain kana recognition quiz (`KanaQuizView`), not some other exercise
/// type:
///   - `mockDue=0`/`mockMastered=0` seed zero kanji/vocabulary cards at all
///     (`TestFixtures.seedContentCards` short-circuits when both are 0).
///   - `mockLevel=30` maxes `masteredCount` (82) + the fixed 10-card
///     "learning" band to exactly 92 — see `TestFixtures.seedKana`'s doc
///     comment — leaving zero cards with `fsrsState.reps == 0`. That matters
///     because `NewCardPresentationScheduler` only schedules the
///     stroke-trace presentation phase for `reps == 0` cards
///     (`SessionComposer.swift`); with none in the pool, every composed
///     exercise is a straight quiz rather than a new-card presentation,
///     which is a different view with a different interaction.
/// The 10 "learning"-band cards are seeded overdue, so they compose into
/// the session; the 82 "mastered" cards are seeded not-yet-due and are
/// excluded by the due-first planner.
///
/// KNOWN FAILURE as of this writing (measured): a full run timed out
/// waiting for `kanaQuiz.optionButton` (~30s, see the run's xcresult).
/// Root cause NOT yet diagnosed — unlike `CloudBackupToggleUITests`, no
/// accessibility-hierarchy dump was captured for this one before this
/// effort's time ran out. Two candidates worth checking first: (1) the same
/// first-run feature-tour overlay `CloudBackupToggleUITests` hit, since
/// `-mockProfile` also creates a brand-new profile and nothing in this test
/// suppresses the tour either; (2) the composed session's first exercise
/// not actually being the plain kana quiz this file's header comment
/// predicts (the `NewCardPresentationScheduler`/`reps == 0` reasoning is
/// sound on paper but was never confirmed against a live hierarchy dump
/// the way the cloud-backup failure was).
/// ⚠️ STILL RED, deliberately left so, and measured — not assumed.
///
/// Adding `skipTour` did NOT fix it, which is itself the useful result: the
/// feature tour hijacking navigation (the cause of the cloud-toggle failures)
/// is not what breaks this one. The assertion still reports that the session
/// never reached a kana quiz option.
///
/// Most likely explanation, NOT yet confirmed: this launches with
/// `mockDue(0)` + `mockMastered(0)`, i.e. a profile with nothing due. A
/// session composed from no SRS cards falls back to supplementary exercises,
/// so a kana quiz may simply never appear — in which case the test's
/// expectation is wrong, not the app. That guess is worth checking against
/// the related finding on `AdaptiveSessionViewModelTests.loadSessionPreview`
/// (PR #103), where an empty profile produced 25 composed items instead of 0.
///
/// It would have been easy to raise `mockDue` until this went green. That
/// would have hidden the question of what the app is supposed to do for a
/// learner with nothing due — which is a real product question, and belongs
/// to whoever answers it, not to a fixture tweak.
final class SessionAnswerFlowUITests: IkeruUITestCase {

    func testStartSessionAndAnswerOneExercise() {
        let app = launch([
            LaunchArguments.mockProfile,
            LaunchArguments.skipTour,
            LaunchArguments.mockLevel(30),
            LaunchArguments.mockDue(0),
            LaunchArguments.mockMastered(0),
            LaunchArguments.autoStartSession,
            LaunchArguments.startTab(1), // Practice/Home
        ])

        let quiz = KanaQuizPage(app: app)
        XCTAssertTrue(
            quiz.waitForOptions(timeout: 15),
            "Session never reached a kana quiz option — either the session " +
            "didn't auto-start, or the composed exercise wasn't the expected quiz type"
        )

        quiz.answerCurrentCard(testCase: self)

        // Answering should not crash the session. With 10 overdue cards
        // queued, one answer never ends the session (see this file's header
        // comment), so the strong assertion is that another quiz option is
        // queued right after — not just "the app is still running", which
        // would also be true of a silent crash-to-background.
        XCTAssertTrue(
            quiz.waitForOptions(timeout: 10),
            "No next quiz card appeared after answering — session may have stalled"
        )
        XCTAssertEqual(
            app.state, .runningForeground,
            "App left the foreground after answering an exercise"
        )
    }
}
