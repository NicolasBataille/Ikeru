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

    static func hasSeenSwipeTutorial(profileID: UUID) -> Bool {
        UserDefaults.standard.bool(forKey: key(swipeTutorial, profileID))
    }

    static func markSwipeTutorialSeen(profileID: UUID) {
        UserDefaults.standard.set(true, forKey: key(swipeTutorial, profileID))
    }
}
