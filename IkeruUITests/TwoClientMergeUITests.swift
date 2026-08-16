import XCTest

/// GAP-01 (severity HAUTE): the two-client cloud-sync merge scenario has
/// never run against two REAL app processes on two REAL simulators before
/// this suite — every other proof of the merge logic (`SyncMergeRulesTests`,
/// `SyncPullDivergenceTests`' `FakeSyncServer`, `LiveSyncVolumeTests`
/// against the live project) ran inside ONE process with at most one
/// identity. This suite is the harness `feat/ui-test-target` (GAP-09) was
/// built to unblock — see that PR's description.
///
/// ## Orchestration — this file alone does NOT run the scenario
///
/// Each `test*` method below is ONE PHASE, meant to be invoked by an
/// external script via `xcodebuild test-without-building
/// -destination id=<UDID> -only-testing:IkeruUITests/TwoClientMergeUITests/<method>`
/// against a SPECIFIC simulator — XCUITest drives one device per invocation,
/// so a two-client scenario is necessarily a SEQUENCE of separate test runs,
/// not one `test` method. Phases must run in the order they're numbered
/// below, alternating between the two simulators, with a Keychain copy
/// (both simulators SHUT DOWN) between phase 1 and phase 2 — see
/// `docs/gap-01-two-client-merge-runbook.md` for the exact commands and the
/// SQL checks that run between phases from outside this file (this suite
/// cannot itself query Supabase — see the "Verification" note below).
///
/// ## Why identity-sharing does not need Sign in with Apple
///
/// Restoring via Apple sign-in (`NameEntryView.performRestoreSync()`) would
/// need a real Apple ID configured on the simulator — a human password,
/// which this suite cannot supply. Instead: phase 1 mints ONE anonymous
/// identity in client A's Keychain (`CloudBackupToggleUITests` already
/// proves this gesture works); the runbook copies that Keychain file to
/// client B's simulator while both are shut down (`AnonymousIdentityManager`
/// never touches network state that a stopped simulator loses); client B's
/// own phase-1 push/pull cycle then runs under the SAME server-side
/// `user_id`, with NO Apple identity involved on either side.
///
/// ## Why the active profile has to be switched by hand
///
/// `CardRepository.activeProfileCards()` (and every other card/review-log
/// query) is scoped to `ActiveProfileResolver`'s active profile — a pull
/// applying a remote `profiles` row never changes which profile is active.
/// Client B's phase-1 sync pulls client A's profile down as a SECOND local
/// profile, but keeps studying its own throwaway one until
/// `-switchToOldestProfile` (added by this effort — see
/// `IkeruApp.initializeProfileViewModel()`) switches it to the OLDER one:
/// client A's, always created first in this phase ordering.
///
/// ## Verification — split between this suite and the runbook operator
///
/// XCUITest cannot read local SwiftData state (it drives the app as a
/// black box) or query Supabase directly. What THIS suite proves, per
/// phase: the UI gestures fire without crashing or stalling — the toggle
/// flips, the drill answers, the resync completes. What the RUNBOOK's SQL
/// checks prove (against `aiayzlarixlogcoyswna`, filtered to the ONE
/// `user_id` this run created): the `review_logs` union (2 per card, one
/// per device, no duplicate ids) actually reached the server, and the
/// `cards` row's `payload->fsrsState->reps` reflects BOTH devices' review
/// having been replayed in (`SyncPullActor.replayFSRS`) — not just
/// whichever device pushed last.
///
/// ## Safety — production writes, scoped and cleaned up
///
/// Gated behind `IKERU_LIVE_SYNC_TEST=1` (`XCTSkipUnless` in `setUp`), same
/// contract `LiveSyncVolumeTests` (IkeruCore) uses — defaults to SKIPPED
/// everywhere, including CI. For a UI test target, `xcodebuild` only
/// forwards environment variables to the test runner process when prefixed
/// `TEST_RUNNER_` — the runbook sets `TEST_RUNNER_IKERU_LIVE_SYNC_TEST=1`,
/// not the bare name. `testZZZ_DeleteCloudDataFromServer` (named to sort
/// last, but ALSO safe to run standalone/first if an earlier phase failed —
/// the identity survives in the Keychain) erases the live account this run
/// created via the same `delete-account` Edge Function
/// `CloudDataDeletionService`/`LiveSyncVolumeTests` use — the runbook's own
/// SQL check confirms zero rows survive it.
final class TwoClientMergeUITests: IkeruUITestCase {

    override func setUpWithError() throws {
        try super.setUpWithError()
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["IKERU_LIVE_SYNC_TEST"] == "1",
            "GAP-01 two-client merge test skipped — set TEST_RUNNER_IKERU_LIVE_SYNC_TEST=1 " +
            "(xcodebuild forwards TEST_RUNNER_-prefixed vars to the test runner) to opt in. " +
            "Never enabled in CI — see this file's Safety doc comment."
        )
    }

    // MARK: - Phase 1a (client A): mint the shared identity

    /// Run on client A FIRST, on a freshly-erased simulator. Creates client
    /// A's local profile and mints the anonymous identity that phase 1b
    /// will copy to client B — mechanically identical to
    /// `CloudBackupToggleUITests.testTogglingCloudBackupOnUpdatesLocalState`,
    /// duplicated here (rather than reused across files) so this suite's
    /// phase numbering/doc comments stay self-contained for whoever runs
    /// the runbook next.
    func testPhase1a_ClientAMintsIdentity() {
        let app = launch([
            LaunchArguments.skipOnboarding,
            LaunchArguments.skipTour,
            LaunchArguments.startTab(2), // Settings
        ])

        let settings = SettingsPage(app: app)
        XCTAssertTrue(settings.waitForCloudBackupToggle())
        XCTAssertFalse(settings.isCloudBackupOn, "Cloud backup must default to OFF")

        settings.tapCloudBackupToggle() // ON — mints identity, pushes client A's empty profile

        XCTAssertTrue(settings.isCloudBackupOn)
        XCTAssertTrue(
            settings.waitForCloudBackupStatus(),
            "No status line after enabling backup — first push may not have completed"
        )
    }

    // MARK: - Phase 1b (client B): join the SAME identity

    /// Run on client B, on a freshly-erased simulator, AFTER the runbook has
    /// copied client A's Keychain file over (both simulators shut down in
    /// between). Creates client B's OWN local profile, then syncs: the pull
    /// half brings client A's profile down as a second local row (cold
    /// start — client B has never synced before), the push half sends
    /// client B's own profile up. The runbook's SQL check between phase 1a
    /// and phase 2 confirms exactly ONE `auth.users` row exists for this
    /// run — if the Keychain copy didn't work, client B would have minted
    /// its OWN separate anonymous identity here instead, and this phase
    /// would silently "succeed" against a second, unrelated account.
    func testPhase1b_ClientBJoinsSameIdentity() {
        let app = launch([
            LaunchArguments.skipOnboarding,
            LaunchArguments.skipTour,
            LaunchArguments.startTab(2), // Settings
        ])

        let settings = SettingsPage(app: app)
        XCTAssertTrue(settings.waitForCloudBackupToggle())
        XCTAssertFalse(
            settings.isCloudBackupOn,
            "Toggle already ON before this phase ever ran — simulator was not freshly erased"
        )

        settings.tapCloudBackupToggle() // ON — pulls client A's profile, pushes client B's own

        XCTAssertTrue(settings.isCloudBackupOn)
        XCTAssertTrue(settings.waitForCloudBackupStatus())
    }

    // MARK: - Phase 2 (client A): review the shared card pool, offline-then-push

    /// Run on client A with `launchKeepingData` (client A's profile +
    /// Keychain identity from phase 1a must survive). Answers all 5 cards
    /// in the `hVowels` group via Free Practice (chosen because it does not
    /// depend on `dueDate`), then forces a push via `SettingsPage
    /// .forceResync()`.
    func testPhase2_ClientAAnswersVowelPoolAndPushes() {
        let app = launchKeepingData([
            LaunchArguments.skipTour,
            LaunchArguments.startTab(0), // Explore
        ])

        answerVowelPoolViaFreePractice(in: app)

        goToSettingsTab(app)
        let settings = SettingsPage(app: app)
        XCTAssertTrue(settings.waitForCloudBackupToggle())
        XCTAssertTrue(settings.isCloudBackupOn, "Consent from phase 1a did not survive — was launchKeepingData used?")
        settings.forceResync()
        XCTAssertTrue(settings.waitForCloudBackupStatus())
    }

    // MARK: - Phase 3 (client B): switch to client A's profile, pull, review the SAME pool, push

    /// Run on client B with `launchKeepingData` + `-switchToOldestProfile`.
    /// Order matters: resync FIRST (to pull client A's phase-2 cards down
    /// as local rows attached to client A's ALREADY-active-after-the-switch
    /// profile) — see `-switchToOldestProfile`'s own doc comment for why
    /// the switch itself doesn't need to wait on this pull (it acts on
    /// profiles phase 1b already pulled down cold) — THEN navigate to the
    /// SAME `hVowels` pool and answer it again, so both devices genuinely
    /// reviewed the SAME 5 `Card` entities (same UUIDs, pulled from the
    /// server) rather than two disjoint sets that merely share glyphs.
    func testPhase3_ClientBPullsSwitchesAndAnswersSamePool() {
        let app = launchKeepingData([
            LaunchArguments.skipTour,
            LaunchArguments.switchToOldestProfile,
            LaunchArguments.startTab(2), // Settings
        ])

        let settings = SettingsPage(app: app)
        XCTAssertTrue(settings.waitForCloudBackupToggle())
        XCTAssertTrue(settings.isCloudBackupOn, "Consent from phase 1b did not survive — was launchKeepingData used?")
        settings.forceResync() // pulls client A's phase-2 cards + review logs
        XCTAssertTrue(settings.waitForCloudBackupStatus())

        goToExploreTab(app)
        answerVowelPoolViaFreePractice(in: app)

        goToSettingsTab(app)
        settings.forceResync() // pushes client B's own review logs for the SAME 5 cards
        XCTAssertTrue(settings.waitForCloudBackupStatus())
    }

    // MARK: - Phase 4 (client A): pull client B's reviews, converge

    /// Run on client A with `launchKeepingData`. A plain resync — the pull
    /// half is what should trigger `SyncPullActor.replayFSRS` for all 5
    /// shared cards (client A's pre-existing local review logs + client
    /// B's newly-pulled ones), and the push half sends the replayed,
    /// merged state back up. This is the phase the runbook's SQL check
    /// runs immediately after.
    func testPhase4_ClientAPullsClientBReviewsAndConverges() {
        let app = launchKeepingData([
            LaunchArguments.skipTour,
            LaunchArguments.startTab(2), // Settings
        ])

        let settings = SettingsPage(app: app)
        XCTAssertTrue(settings.waitForCloudBackupToggle())
        XCTAssertTrue(settings.isCloudBackupOn)
        settings.forceResync()
        XCTAssertTrue(settings.waitForCloudBackupStatus())
    }

    // MARK: - Phase 5 (client B, optional): pull client A's converged state back

    /// Run on client B with `launchKeepingData`. Proves convergence on
    /// BOTH sides, not just the server: if client B's OWN local replay
    /// (its review logs + client A's, now both locally present after this
    /// pull) produces anything other than what phase 4 already pushed,
    /// `SyncModelActor.pushDirtyCards`'s delta filter would pick the card
    /// back up and push AGAIN this same cycle — the runbook checks
    /// `cards.updated_at` does NOT move past phase 4's value for these 5
    /// cards after this phase runs.
    func testPhase5_ClientBPullsConvergedStateBack() {
        let app = launchKeepingData([
            LaunchArguments.skipTour,
            LaunchArguments.startTab(2), // Settings
        ])

        let settings = SettingsPage(app: app)
        XCTAssertTrue(settings.waitForCloudBackupToggle())
        XCTAssertTrue(settings.isCloudBackupOn)
        settings.forceResync()
        XCTAssertTrue(settings.waitForCloudBackupStatus())
    }

    // MARK: - Cleanup (either client — same account)

    /// Named to sort last, but safe to invoke on its own at any point:
    /// deletes the LIVE production account this run created. Run this on
    /// WHICHEVER client's simulator is still available — both share the
    /// same server-side `user_id` by construction (phase 1), so deleting
    /// from either erases the same account (`ON DELETE CASCADE` from
    /// `auth.users` takes every row in all 8 tables). MUST run even if an
    /// earlier phase failed — see this file's Safety doc comment.
    func testZZZ_DeleteCloudDataFromServer() {
        let app = launchKeepingData([
            LaunchArguments.skipTour,
            LaunchArguments.startTab(2), // Settings
        ])

        let settings = SettingsPage(app: app)
        XCTAssertTrue(settings.waitForCloudBackupToggle())
        guard settings.isCloudBackupOn else {
            XCTFail(
                "Cloud backup is already OFF — either cleanup already ran, or this device " +
                "never completed phase 1. If a live account may still exist, verify by SQL " +
                "and delete by hand rather than assuming this is a clean no-op."
            )
            return
        }
        XCTAssertTrue(settings.waitForDeleteCloudDataRow(), "hasEverBackedUp row never appeared")
        settings.confirmDeleteCloudData()

        // Success flips the toggle back OFF (`SettingsView.deleteCloudDataFromServer`).
        let becomesOff = expectation(for: NSPredicate(format: "value == %@", "Off"), evaluatedWith: app.buttons["settings.cloudBackupToggle"])
        wait(for: [becomesOff], timeout: 20)
    }

    // MARK: - Shared phase helpers

    /// `IkeruTabBar` is a custom SwiftUI view, not a native `TabView` — its
    /// buttons carry `tabBar.explore`/`tabBar.practice`/`tabBar.settings`
    /// identifiers (added by this effort, `TatamiTabCell`/`BeginnerTabCell`)
    /// rather than showing up under `app.tabBars`.
    private func goToExploreTab(_ app: XCUIApplication) {
        app.buttons["tabBar.explore"].tap()
    }

    private func goToSettingsTab(_ app: XCUIApplication) {
        app.buttons["tabBar.settings"].tap()
    }

    /// Selects the `hVowels` group in `KanaPoolSelectorView` and answers
    /// all 5 of its cards via Free Practice — shared by phases 2 and 3 so
    /// both clients drive the identical gesture sequence against the
    /// identical pool.
    private func answerVowelPoolViaFreePractice(in app: XCUIApplication) {
        let explore = ExplorePage(app: app)
        XCTAssertTrue(explore.waitForKanaRow(), "Explore tab never showed the Kana row")
        explore.tapKanaRow()

        let pool = KanaPoolSelectorPage(app: app)
        pool.dismissExplainerIfPresent()
        XCTAssertTrue(pool.waitForVowelsGroup(), "hVowels group card never appeared")
        pool.selectVowelsGroup()
        pool.tapFreePractice(testCase: self)

        let quiz = KanaQuizPage(app: app)
        XCTAssertTrue(quiz.waitForOptions(), "Free-practice session never reached a quiz option")
        for _ in 0..<5 {
            quiz.answerCurrentCard(testCase: self)
        }
    }
}
