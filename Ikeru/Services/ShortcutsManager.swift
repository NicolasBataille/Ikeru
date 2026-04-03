import Foundation
import AppIntents
import IkeruCore
import os

// MARK: - Start Quiz Shortcut

/// App Intent for "Hey Siri, quiz me" — launches a micro kana quiz session.
struct StartQuizIntent: AppIntent {

    static let title: LocalizedStringResource = "Quiz Me"
    static let description = IntentDescription("Start a quick Japanese quiz.")
    static let openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        Logger.ui.info("Siri Shortcut: Quiz Me triggered")
        await MainActor.run {
            NotificationCenter.default.post(
                name: .startQuizFromShortcut,
                object: nil
            )
        }
        return .result()
    }
}

// MARK: - Review Cards Shortcut

/// App Intent for "Hey Siri, review Japanese" — starts an SRS review session.
struct StartReviewIntent: AppIntent {

    static let title: LocalizedStringResource = "Review Japanese"
    static let description = IntentDescription("Start your daily Japanese review session.")
    static let openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        Logger.ui.info("Siri Shortcut: Review Japanese triggered")
        await MainActor.run {
            NotificationCenter.default.post(
                name: .startReviewFromShortcut,
                object: nil
            )
        }
        return .result()
    }
}

// MARK: - App Shortcuts Provider

/// Provides Siri Shortcut suggestions for the app.
struct IkeruShortcutsProvider: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartQuizIntent(),
            phrases: [
                "Quiz me in \(.applicationName)",
                "Start a quiz in \(.applicationName)",
                "Japanese quiz in \(.applicationName)",
            ],
            shortTitle: "Quiz Me",
            systemImageName: "character.ja"
        )
        AppShortcut(
            intent: StartReviewIntent(),
            phrases: [
                "Review Japanese in \(.applicationName)",
                "Study Japanese in \(.applicationName)",
                "Start review in \(.applicationName)",
            ],
            shortTitle: "Review",
            systemImageName: "book.fill"
        )
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let startQuizFromShortcut = Notification.Name("com.ikeru.shortcut.quiz")
    static let startReviewFromShortcut = Notification.Name("com.ikeru.shortcut.review")
}
