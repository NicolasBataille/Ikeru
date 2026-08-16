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

    // MARK: - Cleanup

    /// Deletes the anonymous account this test created on the live backend.
    ///
    /// These tests toggle real cloud backup, and the app mints a real anonymous
    /// identity on the real Supabase project when it does. Nothing was removing
    /// it: four orphaned accounts accumulated on the production project in a
    /// single morning — one carrying 92 fixture cards — including one minted by
    /// a CI run, because the `ui-test` job runs on every PR. The suite was
    /// judged on "does the test pass" and not on what it left behind.
    ///
    /// Cleanup goes through the app's OWN Settings row rather than calling the
    /// `delete-account` Edge Function directly. The access token lives in the
    /// app's Keychain, which the test process cannot read — and tapping the
    /// real control exercises the deletion path a learner actually uses, so
    /// this doubles as coverage of it.
    ///
    /// Failures here are reported, never swallowed: a silent cleanup failure
    /// would put us straight back to accumulating accounts unnoticed.
    private func deleteCloudAccount(_ app: XCUIApplication) {
        let settings = SettingsPage(app: app)
        guard settings.waitForCloudBackupToggle(), settings.isCloudBackupOn else { return }

        XCTAssertTrue(
            settings.waitForDeleteCloudDataRow(),
            "Cloud data was created but the delete row never appeared — this run may have "
                + "leaked an anonymous account on the live project. Check by SQL."
        )
        settings.confirmDeleteCloudData()

        let becomesOff = expectation(
            for: NSPredicate(format: "value == %@", "Off"),
            evaluatedWith: app.buttons["settings.cloudBackupToggle"]
        )
        wait(for: [becomesOff], timeout: 20)
    }

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

        deleteCloudAccount(app)
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

        // Turning backup OFF does NOT delete what is already on the server —
        // that is the whole point of GAP-15, and it means this test leaks an
        // anonymous account exactly like the one above. Re-enable so the delete
        // row is reachable, then remove the account. The assertion that matters
        // has already been made, above; this is cleanup, not more test.
        settings.tapCloudBackupToggle() // back ON, so the delete row appears
        deleteCloudAccount(app)
    }
}
