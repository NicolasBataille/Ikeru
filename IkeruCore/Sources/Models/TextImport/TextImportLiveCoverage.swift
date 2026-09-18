import Foundation

// MARK: - TextImportLiveCoverage

/// La couverture VIVANTE d'un texte importé (OBS2-062).
///
/// `TextImport.coverage` est un instantané pris à l'import : structurellement
/// incapable de bouger, quoi que l'apprenant apprenne ensuite. Sur une
/// fonctionnalité dont la promesse est « apporte ton texte et apprends-le »,
/// le journal affichait donc une progression qui n'aurait jamais lieu.
///
/// Ici, chaque texte est ré-analysé avec le dictionnaire de MAINTENANT, et la
/// même arithmétique qu'à l'import (`AnalyzedText.coverage(known:)`) donne
/// la couverture du jour. L'instantané stocké n'est pas touché : il reste ce
/// que l'export et la synchro connaissent ; seul l'écran doit bouger.
public enum TextImportLiveCoverage {

    /// Remplace la couverture stockée de chaque import par celle que
    /// `analyze` et `known` donnent aujourd'hui.
    ///
    /// - Parameters:
    ///   - imports: les imports à rafraîchir, dans l'ordre ; l'ordre est gardé.
    ///   - known: les formes dictionnaire connues de l'apprenant — exactement
    ///     ce que le flux d'import passe à `coverage(known:)`.
    ///   - analyze: l'analyseur (`JapaneseTextAnalyzer.analyze`), injecté pour
    ///     que le calcul se teste sans dictionnaire.
    public static func refresh(
        _ imports: [TextImportDTO],
        known: Set<String>,
        analyze: (String) async -> AnalyzedText
    ) async -> [TextImportDTO] {
        var refreshed: [TextImportDTO] = []
        refreshed.reserveCapacity(imports.count)
        for item in imports {
            let analysis = await analyze(item.content)
            refreshed.append(item.replacingCoverage(analysis.coverage(known: known)))
        }
        return refreshed
    }
}

public extension TextImportDTO {
    /// Le même import, avec une autre couverture — pour l'affichage, jamais
    /// pour l'écriture.
    func replacingCoverage(_ coverage: Double?) -> TextImportDTO {
        TextImportDTO(id: id, title: title, content: content, source: source,
                      createdAt: createdAt, coverage: coverage, entryIDs: entryIDs)
    }
}
