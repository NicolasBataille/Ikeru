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
