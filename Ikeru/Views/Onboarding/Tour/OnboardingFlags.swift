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
    private static let caughtUpExplainer = "caughtUpExplainer"
    private static let kanaDrillModesExplainer = "kanaDrillModesExplainer"

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

    /// Whether Sakura's one-time "all caught up — what now?" explainer (shown
    /// the first time Home lands on the quiet state after the learner begun
    /// every chosen kana) has been shown for this profile.
    static func hasSeenCaughtUpExplainer(profileID: UUID) -> Bool {
        UserDefaults.standard.bool(forKey: key(caughtUpExplainer, profileID))
    }

    static func markCaughtUpExplainerSeen(profileID: UUID) {
        UserDefaults.standard.set(true, forKey: key(caughtUpExplainer, profileID))
    }

    /// Whether Sakura's one-time explainer for the kana drill modes (Review
    /// Due / Free Practice / Weak Spots) has been shown for this profile.
    static func hasSeenKanaDrillModesExplainer(profileID: UUID) -> Bool {
        UserDefaults.standard.bool(forKey: key(kanaDrillModesExplainer, profileID))
    }

    static func markKanaDrillModesExplainerSeen(profileID: UUID) {
        UserDefaults.standard.set(true, forKey: key(kanaDrillModesExplainer, profileID))
    }

    /// Every per-profile coach-mark flag. Keep in sync when adding one — both
    /// `clearAll` and `markAllSeen` iterate it.
    private static let allFlags = [
        swipeTutorial,
        firstSessionDailyTermPrompt,
        caughtUpExplainer,
        kanaDrillModesExplainer,
    ]

    /// Removes every per-profile flag for a deleted profile so its UserDefaults
    /// entries don't accumulate forever (mirrors the ExerciseOutcomeLog cleanup
    /// in `ProfileViewModel.deleteProfile`).
    static func clearAll(profileID: UUID) {
        for name in allFlags {
            UserDefaults.standard.removeObject(forKey: key(name, profileID))
        }
    }

    /// Marks every coach-mark as already seen — the exact inverse of
    /// `clearAll`, and the only writer a UI test needs.
    ///
    /// Why this exists: these coach-marks are *overlays*. The swipe tutorial
    /// (`ActiveSessionView.maybeShowSwipeTutorial`) covers the whole card and
    /// its grade buttons behind a "Got it" scrim the moment a session shows
    /// its first card, and Sakura's caught-up explainer does the same on Home.
    /// A test that isn't about the coach-mark itself can neither see nor tap
    /// what it came for, and the failure reads as a missing element rather
    /// than as a hijacked screen — measured 2026-08-16, it is one of the two
    /// reasons `SessionAnswerFlowUITests` could never pass.
    ///
    /// Deliberately reuses the same `mark…Seen` keys real dismissal writes,
    /// so a suppressed test still exercises the production code path. Kept
    /// separate from `-skipTour` (which owns the *tab tour*, a different
    /// controller) so a future test that wants to assert on a coach-mark can
    /// simply not pass this flag.
    static func markAllSeen(profileID: UUID) {
        for name in allFlags {
            UserDefaults.standard.set(true, forKey: key(name, profileID))
        }
    }
}
