import XCTest

/// Shared launch plumbing for every GAP-09 UI test.
///
/// Two deliberate choices, both load-bearing:
///
/// 1. `-AppleLanguages (en)` is forced on every launch. The app's strings are
///    bilingual (`Localizable.xcstrings`, FR + EN — see CLAUDE.md's
///    localization section), so any test that matched on visible label text
///    would break the moment the simulator's language differs from what the
///    author ran locally. Every page object in `Pages/` locates elements by
///    `accessibilityIdentifier` instead, which is untranslated — this launch
///    override is belt-and-braces on top of that, not a substitute for it.
/// 2. `LaunchArguments.wipeData` is passed BEFORE any seeding flag on every
///    call to `launch(_:)`, so each test starts from a clean slate on
///    whatever simulator runs it — including a second run of the SAME test
///    on a simulator that was never erased between CI jobs. Without it,
///    `-mockProfile` / `-skipOnboarding` silently no-op on the second launch
///    (`ProfileViewModel.hasProfile` is already true) and the test would
///    either fail confusingly or, worse, pass against leftover state from a
///    previous run.
class IkeruUITestCase: XCTestCase {

    override func setUpWithError() throws {
        try super.setUpWithError()
        continueAfterFailure = false
    }

    /// Launches a fresh `XCUIApplication`, always wiping state first.
    /// `extraArguments` are appended after `wipeData` — pass seeding flags
    /// (`-mockProfile`, `-skipOnboarding`, `-startTab=`, ...) here.
    @discardableResult
    func launch(_ extraArguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [LaunchArguments.wipeData] + extraArguments
        app.launchArguments += ["-AppleLanguages", "(en)"]
        app.launch()
        return app
    }

    /// GAP-01 two-client merge test only. Launches WITHOUT `wipeData` — the
    /// opposite of `launch(_:)`'s deliberate always-wipe default, needed
    /// here because that test's later phases (answering cards, re-toggling
    /// cloud sync, switching the active profile) must build on state a
    /// PREVIOUS phase's launch of the SAME app already left behind on this
    /// simulator. Every other suite keeps using `launch(_:)` — do not widen
    /// this method's use beyond the multi-phase merge test without
    /// re-reading `launch(_:)`'s own doc comment for why wiping is the
    /// correct default everywhere else.
    @discardableResult
    func launchKeepingData(_ extraArguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = extraArguments + ["-AppleLanguages", "(en)"]
        app.launch()
        return app
    }
}
