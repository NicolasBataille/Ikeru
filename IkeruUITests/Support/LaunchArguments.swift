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

    /// Seeds a rich fixture profile (kana + kanji/vocab review history).
    /// No-ops if a profile already exists — always pair with `wipeData`.
    static let mockProfile = "-mockProfile"

    static func mockLevel(_ level: Int) -> String { "-mockLevel=\(level)" }
    static func mockDue(_ due: Int) -> String { "-mockDue=\(due)" }
    static func mockMastered(_ mastered: Int) -> String { "-mockMastered=\(mastered)" }

    /// 0 = explore, 1 = practice (default), 2 = settings — see `AppTab`.
    static func startTab(_ tab: Int) -> String { "-startTab=\(tab)" }

    /// Jumps straight into an active session on Home's first appearance —
    /// skips having to locate and tap the "BEGIN PRACTICE" CTA, which is
    /// only present when `HomeViewModel` has composed a non-empty session
    /// (timing-sensitive to wait on from a UI test).
    static let autoStartSession = "-autoStartSession"
}
