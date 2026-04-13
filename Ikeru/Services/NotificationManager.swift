import Foundation
import UserNotifications
import SwiftData
import IkeruCore
import os

// MARK: - NotificationManager

/// Manages local push notifications for SRS review reminders and weekly check-ins.
/// Positive framing only — "X cards ready", never "X days missed".
@MainActor
final class NotificationManager {

    static let shared = NotificationManager()

    private init() {}

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
            Logger.ui.info("Notification authorization: \(granted)")
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
            Logger.ui.info("Review reminder scheduled at \(hour):00")
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
            Logger.ui.info("Weekly check-in scheduled: weekday=\(weekday), hour=\(hour)")
        } catch {
            Logger.ui.error("Failed to schedule check-in: \(error.localizedDescription)")
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
