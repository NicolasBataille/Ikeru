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
        await NotificationManager.shared.postLocalNotification(
            title: "Audio ready",
            body: "Tomorrow's reviews are pre-warmed and waiting.",
            identifier: "ikeru.prewarm.batch-finished"
        )
    }
}
