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
    func requestAuthorization() async -> Bool {
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

    // MARK: - SRS Review Reminders

    /// Schedules a daily review reminder at the specified hour.
    /// - Parameters:
    ///   - hour: Hour of day (0-23) for the reminder.
    ///   - dueCardCount: Number of cards currently due (for the message).
    func scheduleReviewReminder(hour: Int, dueCardCount: Int) {
        let center = UNUserNotificationCenter.current()

        // Remove existing review reminders
        center.removePendingNotificationRequests(withIdentifiers: ["ikeru.review.daily"])

        let content = UNMutableNotificationContent()
        content.title = "Ready to study?"
        content.body = dueCardCount > 0
            ? "\(dueCardCount) cards ready for review!"
            : "Keep your streak going — new cards are waiting!"
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

        center.add(request) { error in
            if let error {
                Logger.ui.error("Failed to schedule review reminder: \(error.localizedDescription)")
            } else {
                Logger.ui.info("Review reminder scheduled at \(hour):00")
            }
        }
    }

    // MARK: - Weekly Check-In

    /// Schedules a weekly check-in notification on the specified day and hour.
    /// - Parameters:
    ///   - weekday: Day of week (1=Sunday, 7=Saturday).
    ///   - hour: Hour of day (0-23).
    func scheduleWeeklyCheckIn(weekday: Int, hour: Int) {
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

        center.add(request) { error in
            if let error {
                Logger.ui.error("Failed to schedule check-in: \(error.localizedDescription)")
            } else {
                Logger.ui.info("Weekly check-in scheduled: weekday=\(weekday), hour=\(hour)")
            }
        }
    }

    // MARK: - Cancel

    /// Removes all scheduled notifications.
    func cancelAll() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        Logger.ui.info("All notifications cancelled")
    }

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
