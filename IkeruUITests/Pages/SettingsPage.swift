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

    @discardableResult
    func waitForCloudBackupToggle(timeout: TimeInterval = 10) -> Bool {
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
}
