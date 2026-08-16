import Foundation

/// Launch-argument constants mirrored from `Ikeru/Support/AppEnvironment.swift`
/// and `Ikeru/Support/TestFixtures.swift`. Kept in the UI test target (not
/// shared with the app target) because XCUITest launches the app as a
/// separate process — there is no compiled dependency to share these from,
/// only the string contract itself.
///
/// GAP-09 (UI test harness): every flag here already existed in the app
/// before this target was added, EXCEPT `wipeData`, which this effort added
/// (`IkeruApp.initializeProfileViewModel()`, gated `#if IKERU_DEV_TOOLS`
/// exactly like the others) specifically to make UI tests re-runnable on the
/// same simulator without a manual erase between runs — see its doc comment
/// for why that matters (`seedIfRequested` / the `-skipOnboarding` guard both
/// no-op once a profile exists).
enum LaunchArguments {
    /// Wipes all persisted state (profiles, cards, RPG state, chat, vocab)
    /// before `-skipOnboarding` / `-mockProfile` run. Always pass this first
    /// in a UI test's `launchArguments` so each test starts from a clean
    /// slate regardless of what a previous test left behind.
    static let wipeData = "-wipeData"

    /// Auto-creates a plain "Nico" profile with no fixture content.
    static let skipOnboarding = "-skipOnboarding"

    /// Marks the feature tour as already seen for the profile that was just
    /// created, so it never starts.
    ///
    /// Pair this with `startTab(_:)` — without it the two do not compose, and
    /// the failure is silent. Creating a profile starts the tour, and the tour
    /// drives navigation itself (`MainTabView.syncTabToTourStep()`), so it
    /// overwrites the tab `startTab(_:)` asked for. The test lands somewhere
    /// it never requested and reports a missing element, which reads like a
    /// broken accessibility identifier rather than a hijacked route.
    static let skipTour = "-skipTour"

    /// Marks every in-context coach-mark as already dismissed for the profile
    /// that was just created.
    ///
    /// Pair this with anything that reaches a session or a caught-up Home —
    /// and note it is NOT what `skipTour` does. Measured 2026-08-16: with only
    /// `skipTour`, a session opens and `SwipeTutorialView` immediately covers
    /// the card and its grade buttons behind a "Got it" scrim
    /// (`ActiveSessionView.maybeShowSwipeTutorial`). The test then reports a
    /// missing element while a screenshot shows the app working perfectly —
    /// one of the two reasons `SessionAnswerFlowUITests` could never pass.
    static let skipHints = "-skipHints"

    /// Seeds a rich fixture profile (kana + kanji/vocab review history).
    /// No-ops if a profile already exists — always pair with `wipeData`.
    static let mockProfile = "-mockProfile"

    static func mockLevel(_ level: Int) -> String { "-mockLevel=\(level)" }
    static func mockDue(_ due: Int) -> String { "-mockDue=\(due)" }
    static func mockMastered(_ mastered: Int) -> String { "-mockMastered=\(mastered)" }

    /// Seeds a profile with **nothing due right now** — every kana and every
    /// content card begun and scheduled comfortably ahead.
    ///
    /// `mockDue(0)` does NOT do this, which is the trap this flag was added
    /// for. Measured 2026-08-16: `mockDue` governs only the kanji/vocabulary
    /// pool (`TestFixtures.seedContentCards`), while `seedKana` seeds its own
    /// 92 characters from `mockLevel` — a fixed 10-card overdue band at every
    /// level, plus never-reviewed cards (due today) for the rest. So a
    /// `-mockDue=0` profile always had something due, and the two caught-up
    /// tests that assumed otherwise could not pass at any slider setting.
    ///
    /// Overrides `mockDue`; `mockMastered` still applies (as mastered content).
    /// One consequence to design around: with no never-reviewed card left, the
    /// caught-up proposal offers **deepen** and not **discover** — a card
    /// nobody has reviewed is itself due, so the two cannot coexist.
    static let mockNothingDue = "-mockNothingDue"

    /// 0 = explore, 1 = practice (default), 2 = settings — see `AppTab`.
    static func startTab(_ tab: Int) -> String { "-startTab=\(tab)" }

    /// Jumps straight into an active session on Home's first appearance —
    /// skips having to locate and tap the "BEGIN PRACTICE" CTA, which is
    /// only present when `HomeViewModel` has composed a non-empty session
    /// (timing-sensitive to wait on from a UI test).
    static let autoStartSession = "-autoStartSession"

    /// GAP-01 two-client merge test only. After a cold-start pull has
    /// applied a REMOTE `profiles` row alongside this device's own local
    /// one (see `CardRepository.activeProfileCards()` — every card/review
    /// query is scoped to `ActiveProfileResolver`'s active profile, which a
    /// pull never changes on its own), switches the active profile to the
    /// OLDEST local one (by `createdAt`) — i.e. the one the OTHER client
    /// created first, in this test's phase ordering. Handled in
    /// `IkeruApp.initializeProfileViewModel()`, gated `#if IKERU_DEV_TOOLS`
    /// like every other flag here. A no-op if only one profile exists
    /// locally (nothing to switch to).
    static let switchToOldestProfile = "-switchToOldestProfile"
}
