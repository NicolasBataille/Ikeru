import XCTest

/// Covers the « apporte ton propre texte » journey end to end, on a real
/// simulator, because the only thing unit tests cannot check is whether the
/// screen is reachable at all.
final class TextImportUITests: IkeruUITestCase {

    func testExploreOffersTheTextImportRow() {
        let app = launch([
            LaunchArguments.skipOnboarding,
            LaunchArguments.skipTour,
            LaunchArguments.startTab(0),
        ])
        let row = app.buttons["explore.textImportRow"]
        if !row.waitForExistence(timeout: 15) {
            // Le message d'échec porte l'arbre : sans lui, « élément absent »
            // ne dit pas si la vue est absente, mal identifiée, ou hors écran.
            XCTFail("Ligne absente de l'onglet Étude.\n\(app.debugDescription)")
        }
    }
}
