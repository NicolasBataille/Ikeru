import XCTest

/// Covers the « apporte ton propre texte » journey end to end, on a real
/// simulator, because the only thing unit tests cannot check is whether the
/// screen is reachable at all.
final class TextImportUITests: IkeruUITestCase {

    /// Le parcours doit RESTER franchissable de bout en bout.
    ///
    /// Mesuré le 2026-08-19 : le pied de l'étape de lecture était dessiné SOUS
    /// la barre d'onglets flottante, donc « choisir les mots à apprendre »
    /// existait, se testait vert en unitaire, et était **intappable**. Le
    /// parcours s'arrêtait là, sans message d'erreur ni indice. Aucun test
    /// unitaire ne peut voir ça : il faut un vrai écran et un vrai tap.
    func testTheJourneyIsWalkableToTheEnd() {
        let app = launch([
            LaunchArguments.skipOnboarding,
            LaunchArguments.skipTour,
            LaunchArguments.skipHints,
            LaunchArguments.startTab(0),
        ])
        let row = app.buttons["explore.textImportRow"]
        XCTAssertTrue(row.waitForExistence(timeout: 20),
                      "ligne d'import absente.\n\(app.debugDescription)")
        row.tap()

        // Saisie directe : le presse-papiers du simulateur demande une
        // autorisation système que le test ne peut pas accorder de façon fiable.
        //
        // ⚠️ Les boutons se cherchent par IDENTIFIANT, jamais par libellé : le
        // harnais force `-AppleLanguages (en)` (voir `IkeruUITestCase.launch`),
        // donc un libellé français ne matche jamais — et l'anglais casserait au
        // premier reformulage.
        let field = app.textViews.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 10), "champ de saisie absent")
        field.tap()
        field.typeText("犬が公園にいます。")

        let readButton = app.buttons["textImport.analyze"]
        XCTAssertTrue(readButton.waitForExistence(timeout: 10), "bouton d'analyse absent")
        XCTAssertTrue(readButton.isEnabled, "le bouton d'analyse reste désactivé après saisie")
        readButton.tap()

        // Le point de la panne : le bouton existe-t-il ET est-il atteignable ?
        let toSelection = app.buttons["textImport.toSelection"]
        XCTAssertTrue(toSelection.waitForExistence(timeout: 20),
                      "l'étape de lecture n'offre pas de suite.\n\(app.debugDescription)")
        XCTAssertTrue(toSelection.isHittable,
                      "le bouton existe mais rien ne peut le toucher — dessiné sous la barre ?")
        toSelection.tap()

        // Et la sélection doit à son tour offrir sa sortie.
        let save = app.buttons["textImport.save"]
        XCTAssertTrue(save.waitForExistence(timeout: 15),
                      "l'écran de sélection n'offre pas d'enregistrement.\n\(app.debugDescription)")
        XCTAssertTrue(save.isHittable, "bouton d'enregistrement intappable")
    }

    func testExploreOffersTheTextImportRow() {
        let app = launch([
            LaunchArguments.skipOnboarding,
            LaunchArguments.skipTour,
            LaunchArguments.skipHints,
            LaunchArguments.startTab(0),
        ])
        let row = app.buttons["explore.textImportRow"]
        if !row.waitForExistence(timeout: 20) {
            // Le message d'échec porte l'arbre : sans lui, « élément absent »
            // ne dit pas si la vue est absente, mal identifiée, ou hors écran.
            XCTFail("Ligne absente de l'onglet Étude.\n\(app.debugDescription)")
        }
    }
}
