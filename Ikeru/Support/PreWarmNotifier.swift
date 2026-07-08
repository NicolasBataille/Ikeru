import Foundation

/// Thin shim that posts the "pre-warm batch finished" local notification via
/// the shared `NotificationManager`. Kept as a free-standing helper so callers
/// (BG task body, Settings "Pre-warm now" button) don't need to know about the
/// notification identifier or copy.
///
/// All authorization gating (skipping the system prompt when already
/// determined) lives in `NotificationManager.requestAuthorization()`.
enum PreWarmNotifier {

    static func notifyBatchFinished() async {
        // `String(localized:)` at the call site — `postLocalNotification`
        // takes plain `String`s, so a bare literal here would ship
        // English-only (same pattern as NotificationManager's own copy).
        await NotificationManager.shared.postLocalNotification(
            title: String(localized: "Audio ready"),
            body: String(localized: "Tomorrow's reviews are pre-warmed and waiting."),
            identifier: "ikeru.prewarm.batch-finished"
        )
    }
}
