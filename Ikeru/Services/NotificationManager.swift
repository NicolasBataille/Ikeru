import Foundation
import UserNotifications
import SwiftData
import IkeruCore
import os

// MARK: - NotificationManager

/// Manages local push notifications for SRS review reminders, weekly
/// check-ins, and the daily term reveal. Positive framing only — "X cards
/// ready", never "X days missed".
///
/// Also routes notification taps via `UNUserNotificationCenterDelegate`
/// so deep-link payloads (e.g. the daily-term reminder) can wake the
/// matching surface in the app.
@MainActor
final class NotificationManager: NSObject, @preconcurrency UNUserNotificationCenterDelegate {

    static let shared = NotificationManager()

    /// Hooks the manager up as the user-notification centre delegate so it
    /// can react to taps and foreground deliveries. Idempotent.
    func registerAsDelegate() {
        UNUserNotificationCenter.current().delegate = self
    }

    private override init() {
        super.init()
    }

    // MARK: - Authorization

    /// Requests notification permission from the user.
    /// Skips the system prompt if the authorization status has already been
    /// determined (authorized, denied, provisional, or ephemeral) — we only
    /// prompt when it is still `.notDetermined`.
    func requestAuthorization() async -> Bool {
        let current = await UNUserNotificationCenter.current().notificationSettings()
        switch current.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .denied:
            return false
        case .notDetermined:
            break
        @unknown default:
            break
        }

        do {
            let granted = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
            Logger.ui.info("Notification authorization: \(granted, privacy: .public)")
            return granted
        } catch {
            Logger.ui.error("Notification auth failed: \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - Transient Local Notifications

    /// Posts a transient local notification immediately (no trigger). Honours
    /// the current authorization state via `requestAuthorization()` — if the
    /// user has denied notifications this is a silent no-op.
    func postLocalNotification(title: String, body: String, identifier: String) async {
        let authorized = await requestAuthorization()
        guard authorized else { return }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: nil
        )

        do {
            try await UNUserNotificationCenter.current().add(request)
            Logger.ui.info("Local notification posted: \(identifier, privacy: .public)")
        } catch {
            Logger.ui.error("Failed to post local notification \(identifier, privacy: .public): \(error.localizedDescription)")
        }
    }

    // MARK: - SRS Review Reminders

    /// Schedules a daily review reminder at the specified hour.
    /// - Parameter hour: Hour of day (0-23) for the reminder.
    func scheduleReviewReminder(hour: Int) async {
        let center = UNUserNotificationCenter.current()

        center.removePendingNotificationRequests(withIdentifiers: ["ikeru.review.daily"])

        let content = UNMutableNotificationContent()
        content.title = "Ready to study?"
        content.body = "Keep your streak going — your cards are waiting!"
        content.sound = .default
        content.categoryIdentifier = "REVIEW_REMINDER"

        var dateComponents = DateComponents()
        dateComponents.hour = hour
        dateComponents.minute = 0

        let trigger = UNCalendarNotificationTrigger(
            dateMatching: dateComponents,
            repeats: true
        )

        let request = UNNotificationRequest(
            identifier: "ikeru.review.daily",
            content: content,
            trigger: trigger
        )

        do {
            try await center.add(request)
            Logger.ui.info("Review reminder scheduled at \(hour, privacy: .public):00")
        } catch {
            Logger.ui.error("Failed to schedule review reminder: \(error.localizedDescription)")
        }
    }

    // MARK: - Weekly Check-In

    /// Schedules a weekly check-in notification on the specified day and hour.
    /// - Parameters:
    ///   - weekday: Day of week (1=Sunday, 7=Saturday).
    ///   - hour: Hour of day (0-23).
    func scheduleWeeklyCheckIn(weekday: Int, hour: Int) async {
        let center = UNUserNotificationCenter.current()

        center.removePendingNotificationRequests(withIdentifiers: ["ikeru.checkin.weekly"])

        let content = UNMutableNotificationContent()
        content.title = "Weekly Check-In"
        content.body = "How's your Japanese journey going? Take a moment to reflect."
        content.sound = .default
        content.categoryIdentifier = "WEEKLY_CHECKIN"

        var dateComponents = DateComponents()
        dateComponents.weekday = weekday
        dateComponents.hour = hour

        let trigger = UNCalendarNotificationTrigger(
            dateMatching: dateComponents,
            repeats: true
        )

        let request = UNNotificationRequest(
            identifier: "ikeru.checkin.weekly",
            content: content,
            trigger: trigger
        )

        do {
            try await center.add(request)
            Logger.ui.info("Weekly check-in scheduled: weekday=\(weekday, privacy: .public), hour=\(hour, privacy: .public)")
        } catch {
            Logger.ui.error("Failed to schedule check-in: \(error.localizedDescription)")
        }
    }

    // MARK: - Daily Term

    /// Schedules a recurring local notification for the daily term reveal.
    /// - Parameters:
    ///   - hour: Hour of day (0-23).
    ///   - minute: Minute (0-59).
    func scheduleDailyTermReminder(hour: Int, minute: Int) async {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [Self.dailyTermIdentifier])

        let content = UNMutableNotificationContent()
        content.title = "A new word is waiting"
        content.body = "Today's term is ready to discover — tap to reveal it."
        content.sound = .default
        content.categoryIdentifier = Self.dailyTermCategory
        // Carry a routing hint so the delegate can deep-link without
        // having to inspect the request identifier.
        content.userInfo = ["ikeru.deeplink": "dailyTerm"]

        var dateComponents = DateComponents()
        dateComponents.hour = max(0, min(23, hour))
        dateComponents.minute = max(0, min(59, minute))

        let trigger = UNCalendarNotificationTrigger(
            dateMatching: dateComponents,
            repeats: true
        )

        let request = UNNotificationRequest(
            identifier: Self.dailyTermIdentifier,
            content: content,
            trigger: trigger
        )

        do {
            try await center.add(request)
            Logger.ui.info("Daily term reminder scheduled at \(dateComponents.hour ?? 0, privacy: .public):\(String(format: "%02d", dateComponents.minute ?? 0), privacy: .public)")
        } catch {
            Logger.ui.error("Failed to schedule daily term reminder: \(error.localizedDescription)")
        }
    }

    /// Removes the daily term reminder.
    func cancelDailyTermReminder() {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [Self.dailyTermIdentifier])
    }

    static let dailyTermIdentifier = "ikeru.dailyterm.daily"
    static let dailyTermCategory = "DAILY_TERM"

    // MARK: - UNUserNotificationCenterDelegate

    /// Foreground delivery — show the banner so the user notices, but
    /// don't auto-route to the reveal sheet (they may be mid-task).
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .list])
    }

    /// Tap response — if the daily-term reminder, post a notification so
    /// the home view can present the reveal sheet.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        defer { completionHandler() }
        guard response.actionIdentifier == UNNotificationDefaultActionIdentifier else { return }

        let content = response.notification.request.content
        let isDailyTerm = response.notification.request.identifier == Self.dailyTermIdentifier
            || (content.userInfo["ikeru.deeplink"] as? String) == "dailyTerm"

        if isDailyTerm {
            Logger.ui.info("Daily term notification tapped — routing to reveal")
            NotificationCenter.default.post(name: .openDailyTerm, object: nil)
        }
    }

    // MARK: - Cancel

    /// Removes review reminders only.
    func cancelReviewReminders() {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: ["ikeru.review.daily"])
    }

    /// Removes weekly check-in only.
    func cancelWeeklyCheckIn() {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: ["ikeru.checkin.weekly"])
    }
}
