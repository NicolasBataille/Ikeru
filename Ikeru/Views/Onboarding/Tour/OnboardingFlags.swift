import Foundation

// MARK: - Onboarding Flags
//
// One-shot, per-profile "have they seen this hint yet?" flags for the
// feature-level coach-marks (e.g. the card swipe tutorial). The tab tour has
// its own controller; this is for the lighter, in-context demos that fire the
// first time a user reaches a particular surface.

enum OnboardingFlags {
    private static func key(_ name: String, _ profileID: UUID) -> String {
        "ikeru.onboarding.\(name).\(profileID.uuidString)"
    }

    private static let swipeTutorial = "swipeTutorial"
    private static let firstSessionDailyTermPrompt = "firstSessionDailyTermPrompt"

    static func hasSeenSwipeTutorial(profileID: UUID) -> Bool {
        UserDefaults.standard.bool(forKey: key(swipeTutorial, profileID))
    }

    static func markSwipeTutorialSeen(profileID: UUID) {
        UserDefaults.standard.set(true, forKey: key(swipeTutorial, profileID))
    }

    /// Whether the one-time "enable daily term?" prompt (shown right after the
    /// learner's first-ever completed session) has already been shown for this
    /// profile — regardless of whether they accepted or declined.
    static func hasSeenFirstSessionDailyTermPrompt(profileID: UUID) -> Bool {
        UserDefaults.standard.bool(forKey: key(firstSessionDailyTermPrompt, profileID))
    }

    static func markFirstSessionDailyTermPromptSeen(profileID: UUID) {
        UserDefaults.standard.set(true, forKey: key(firstSessionDailyTermPrompt, profileID))
    }

    /// Removes every per-profile flag for a deleted profile so its UserDefaults
    /// entries don't accumulate forever (mirrors the ExerciseOutcomeLog cleanup
    /// in `ProfileViewModel.deleteProfile`). Keep in sync with the flag list
    /// above.
    static func clearAll(profileID: UUID) {
        for name in [swipeTutorial, firstSessionDailyTermPrompt] {
            UserDefaults.standard.removeObject(forKey: key(name, profileID))
        }
    }
}
