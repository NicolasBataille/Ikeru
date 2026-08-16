import XCTest

/// Page object for the Settings tab, scoped to the cloud-backup row —
/// GAP-09's priority deliverable. This is the gesture GAP-01's two-client
/// merge test is blocked on: cloud sync only starts from
/// `CloudSyncCoordinator.setConsent()`, and the only UI path to that call is
/// `SettingsView.handleCloudSyncToggleChange(_:)`, wired to this toggle.
///
/// Identifiers used here (`settings.cloudBackupToggle`,
/// `settings.cloudBackupStatus`) are set in `Ikeru/Views/Settings/SettingsView.swift`
/// and `Ikeru/Views/Shared/Theme/TatamiToggle.swift` — added by this same
/// effort (the app had zero `accessibilityIdentifier`s before GAP-09).
///
/// Deliberately does NOT assert sync ever reaches the server: the toggle
/// fires a real, fire-and-forget network call to Ikeru's production Supabase
/// project (see CLAUDE.md "Sauvegarde cloud Supabase"). Asserting on that
/// outcome from a UI test would be flaky in CI (network-dependent) and would
/// write real rows against the production anonymous-identity project on
/// every CI run. What's verified here is the LOCAL, immediately-observable
/// contract: the toggle's own on/off state and that turning it on produces
/// a status line at all. A future two-client sync test (GAP-01) is the right
/// place to assert on network outcomes, against a project meant for that.
struct SettingsPage {
    let app: XCUIApplication

    private var cloudBackupToggle: XCUIElement {
        app.buttons["settings.cloudBackupToggle"]
    }

    private var cloudBackupStatus: XCUIElement {
        app.staticTexts["settings.cloudBackupStatus"]
    }

    /// 25s default (not 10s): GAP-01's multi-phase merge test relaunches
    /// the app on a profile that already carries a pulled-down second
    /// profile plus review history — measured slower to reach Settings on
    /// a freshly-erased simulator than the single-profile, no-sync-history
    /// case the original 10s default was tuned for.
    @discardableResult
    func waitForCloudBackupToggle(timeout: TimeInterval = 25) -> Bool {
        cloudBackupToggle.waitForExistence(timeout: timeout)
    }

    /// `TatamiToggle` is a custom `Button`, not a native `Toggle` — its
    /// on/off state is exposed via `.accessibilityValue("On"/"Off")`
    /// (`TatamiToggle.swift`), not the native `Toggle` `.value` (isOn/isOff).
    var isCloudBackupOn: Bool {
        cloudBackupToggle.value as? String == "On"
    }

    func tapCloudBackupToggle() {
        cloudBackupToggle.tap()
    }

    @discardableResult
    func waitForCloudBackupStatus(timeout: TimeInterval = 10) -> Bool {
        cloudBackupStatus.waitForExistence(timeout: timeout)
    }

    // MARK: - GAP-01 two-client merge test only

    /// Forces a fresh, deterministic `syncNow(ignoringThrottle: true)` cycle
    /// without waiting on `CloudSyncTriggers`' foreground/network-regain
    /// triggers or the 60s `minSyncInterval` — see
    /// `CloudSyncCoordinator.setConsent`'s doc comment: turning the toggle
    /// OFF resets every pull cursor, and turning it back ON always fires an
    /// `ignoringThrottle: true` sync (`SettingsView.handleCloudSyncToggleChange`).
    /// Requires the toggle to already be ON — callers that need the FIRST
    /// sync (identity not minted yet) should call `tapCloudBackupToggle()`
    /// once instead.
    func forceResync() {
        tapCloudBackupToggle() // OFF — resets cursors
        tapCloudBackupToggle() // ON — syncNow(ignoringThrottle: true)
    }

    private var deleteCloudDataRow: XCUIElement {
        app.buttons["settings.deleteCloudDataRow"]
    }

    @discardableResult
    func waitForDeleteCloudDataRow(timeout: TimeInterval = 10) -> Bool {
        deleteCloudDataRow.waitForExistence(timeout: timeout)
    }

    /// Drives the full "Delete my data from the server" flow — the row,
    /// the confirmation alert, and its destructive "Delete" button.
    /// `CloudDataDeletionService.deleteAllCloudData()` (wired from
    /// `SettingsView.deleteCloudDataFromServer()`) is what actually calls
    /// the production `delete-account` Edge Function — see
    /// `LiveSyncVolumeTests` for the same call made directly, without a UI.
    func confirmDeleteCloudData() {
        deleteCloudDataRow.tap()
        app.alerts.firstMatch.buttons["Delete"].tap()
    }
}
