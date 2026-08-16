import XCTest

/// GAP-09's priority deliverable: a real, reusable UI-test harness around the
/// cloud-backup toggle gesture that GAP-01 (two-client cloud-sync merge
/// test, severity HAUTE) is blocked on. GAP-01's scenario needs to actually
/// flip this switch on two simulated clients — before this test target
/// existed, `CloudSyncCoordinator.setConsent()` had no caller reachable
/// except from inside the running app, which meant no automated test could
/// reach it at all.
///
/// Scope, deliberately: this test proves the LOCAL UI contract (toggle
/// flips, a status line appears) — see `SettingsPage`'s doc comment for why
/// it does not assert on the network sync outcome.
///
/// Both tests below used to time out, and the diagnosis is worth keeping:
/// `-skipOnboarding` creates a brand-new profile, which starts
/// `FeatureTourController`'s first-run coach marks ("Hi, I'm Sakura!"). That
/// overlay covers the screen AND drives `selectedTab` itself via
/// `MainTabView.syncTabToTourStep()`, overriding `-startTab=2`. The app never
/// reached Settings, and the symptom — a missing element — looked like a
/// broken accessibility identifier rather than a hijacked route.
///
/// Fixed by `LaunchArguments.skipTour`, which calls the existing
/// `FeatureTourController.markSeen(profileID:)` — the same static writer the
/// restore path uses, on the same UserDefaults key `hasSeenTour(profileID:)`
/// reads. Suppressing the tour any other way would have tested a path no
/// learner takes.
///
/// The general lesson, since it will bite again: **`-skipOnboarding` and
/// `-startTab` do not compose on their own.** Pair them with `skipTour`.
final class CloudBackupToggleUITests: IkeruUITestCase {

    /// ⛔ OPT-IN ONLY — this suite writes to the LIVE Supabase project.
    ///
    /// Toggling cloud backup makes the app mint a real anonymous identity on
    /// the production project. Nothing removed it, and these tests ran on every
    /// PR: four orphaned accounts accumulated in one morning, one carrying 92
    /// fixture cards, one of them minted by a CI run.
    ///
    /// The fix is not a better teardown — it is that a test touching a live
    /// backend must be opted into, exactly like
    /// `IkeruCore/Tests/Services/Sync/LiveSyncVolumeTests.swift` already is.
    /// CI runs the other four UI tests, which touch nothing remote.
    ///
    ///     TEST_RUNNER_IKERU_LIVE_SYNC_TEST=1 xcodebuild test \
    ///       -scheme IkeruUITests -destination "id=<sim>" \
    ///       -only-testing:IkeruUITests/CloudBackupToggleUITests
    ///
    /// A teardown was attempted first and is kept below, but it is NOT what
    /// makes this safe: it left consent ON for the next test (`-wipeData` does
    /// not clear the consent default) and the app lost its connection mid
    /// deletion. Cleanup that only mostly works is how the accounts piled up
    /// unnoticed in the first place.
    override func setUpWithError() throws {
        try super.setUpWithError()
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["IKERU_LIVE_SYNC_TEST"] == "1",
            "Cloud-backup UI tests skipped — they write to the live Supabase project. "
                + "Set TEST_RUNNER_IKERU_LIVE_SYNC_TEST=1 to opt in."
        )
    }

    // MARK: - Cleanup — intentionally absent on this branch
    //
    // The upstream commit this gate was cherry-picked from
    // (`test/gap-01-two-client-merge`, 7a2e6be) also carries a teardown that
    // removes the account through the app's own Settings row. It is NOT
    // reproduced here: it drives page-object helpers that arrive with GAP-01's
    // own commit (1625238). Dragging that commit into an unrelated
    // test-infrastructure PR to get two helpers would be worse than going
    // without the teardown.
    //
    // Nothing is lost. That commit's own message is explicit that the teardown
    // "is deliberately not what makes this safe, because it did not work" — it
    // left consent ON for the next test and dropped the runner connection
    // mid-deletion. What makes this safe is the `XCTSkipUnless` gate above,
    // reproduced verbatim: these tests no longer run unless opted into, so
    // there is no account left behind to tear down. The teardown returns for
    // free when GAP-01 lands and this branch rebases.

    func testTogglingCloudBackupOnUpdatesLocalState() {
        let app = launch([
            LaunchArguments.skipOnboarding,
            LaunchArguments.skipTour,
            LaunchArguments.startTab(2), // Settings — see AppTab
        ])

        let settings = SettingsPage(app: app)
        XCTAssertTrue(
            settings.waitForCloudBackupToggle(),
            "Cloud backup toggle never appeared in Settings"
        )
        XCTAssertFalse(settings.isCloudBackupOn, "Cloud backup must default to OFF (opt-in)")

        settings.tapCloudBackupToggle()

        XCTAssertTrue(settings.isCloudBackupOn, "Toggle did not flip to ON after tapping it")
        XCTAssertTrue(
            settings.waitForCloudBackupStatus(),
            "No status line appeared under the toggle after enabling backup"
        )
    }

    func testTogglingCloudBackupOffReturnsToDefaultState() {
        let app = launch([
            LaunchArguments.skipOnboarding,
            LaunchArguments.skipTour,
            LaunchArguments.startTab(2),
        ])

        let settings = SettingsPage(app: app)
        XCTAssertTrue(settings.waitForCloudBackupToggle())

        settings.tapCloudBackupToggle() // ON
        XCTAssertTrue(settings.isCloudBackupOn)

        settings.tapCloudBackupToggle() // OFF
        XCTAssertFalse(settings.isCloudBackupOn, "Toggle did not flip back to OFF")
    }
}
