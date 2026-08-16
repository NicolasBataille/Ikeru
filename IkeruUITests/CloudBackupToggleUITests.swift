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
/// KNOWN FAILURE as of this writing (measured, not assumed — full
/// accessibility-hierarchy dump captured via a temporary `app.debugDescription`
/// print, then removed): both tests below currently time out.
/// `-skipOnboarding` creates a brand-new profile, which makes
/// `MainTabView.onAppear` start `FeatureTourController`'s first-run coach-mark
/// overlay ("Hi, I'm Sakura!") — that overlay covers the whole screen AND
/// (via `syncTabToTourStep()`) drives `selectedTab` itself, overriding
/// `-startTab=2`'s initial value. So the app never actually reaches Settings
/// under `-skipOnboarding`, regardless of `-startTab`. Not fixed here — this
/// effort ran out of budget mid-diagnosis (see PR description / GAP-09
/// report). Two candidate fixes for whoever picks this up: (1) a
/// `-skipFeatureTour` dev-tools launch flag that calls
/// `FeatureTourController.markSeen(profileID:)` before `MainTabView`
/// appears, or (2) have `SettingsPage` dismiss the tour overlay first if
/// present. `DashboardLaunchUITests`/`ProfileResetUITests` don't hit this
/// because they only need Home, which is what the tour spotlights anyway.
final class CloudBackupToggleUITests: IkeruUITestCase {

    func testTogglingCloudBackupOnUpdatesLocalState() {
        let app = launch([
            LaunchArguments.skipOnboarding,
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
