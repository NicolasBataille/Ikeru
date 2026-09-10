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

    /// Fait défiler l'écran vers le haut jusqu'à ce que `element` soit
    /// entièrement AU-DESSUS de la barre d'onglets flottante, et dit si c'est
    /// le cas à la fin.
    ///
    /// Pourquoi : la CI fait tourner les tests UI sur le PLUS PETIT iPhone
    /// disponible (le sélecteur trie par nom, « iPhone SE » passe dernier —
    /// 375 × 667 pt). Une ligne qui « existe » peut y naître sous la barre :
    /// `tap()` vise son centre, la barre avale le tap, et rien ne s'ouvre —
    /// sans erreur. Mesuré le 2026-09-10 sur la ligne d'import d'Étude,
    /// devenue cinquième derrière « Composer une séance ».
    ///
    /// Pourquoi pas `isHittable` : mesuré le même jour, il répond VRAI pour
    /// cette ligne dont le centre est sous la barre — l'arbre d'accessibilité
    /// ne voit pas la barre comme un obstacle — alors que le tap réel, lui,
    /// est avalé. Le seul verdict fiable est géométrique : le cadre de la
    /// ligne contre celui de la barre, qui porte ses propres identifiants
    /// (`tabBar.explore` est toujours là quand la barre l'est).
    func scrollAboveTabBar(_ element: XCUIElement,
                           in app: XCUIApplication,
                           maxSwipes: Int = 4) -> Bool {
        let tabBar = app.buttons["tabBar.explore"]
        guard tabBar.exists else { return element.isHittable }
        var swipes = 0
        while element.frame.maxY > tabBar.frame.minY, swipes < maxSwipes {
            app.swipeUp()
            swipes += 1
        }
        return element.frame.maxY <= tabBar.frame.minY && element.isHittable
    }
}
