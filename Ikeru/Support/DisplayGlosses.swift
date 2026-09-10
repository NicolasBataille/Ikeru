import Foundation
import IkeruCore

/// Résout les gloses du dictionnaire personnel dans la langue de l'interface,
/// pour l'AFFICHAGE (OBS2-041 / P1-5) — un seul point de résolution pour toutes
/// les surfaces : liste du dictionnaire, fiche, flashcard, options du quiz.
///
/// Rien n'est écrit : le sens stocké reste celui de la capture (l'export et
/// la synchro le connaissent) ; seul ce que l'apprenant lit suit sa langue.
/// Sans dictionnaire embarqué, les entrées sont rendues telles quelles.
enum DisplayGlosses {

    /// Un seul dictionnaire ouvert pour toute l'app.
    private static let resolver: GlossResolver? =
        BundledContent.makeDictionary().map { GlossResolver(dictionary: $0) }

    static func resolve(_ entries: [VocabularyEntryDTO], locale: Locale) async -> [VocabularyEntryDTO] {
        guard let resolver else { return entries }
        return await resolver.resolve(entries, into: GlossLanguage(locale: locale))
    }

    static func resolve(_ entry: VocabularyEntryDTO, locale: Locale) async -> VocabularyEntryDTO {
        guard let resolver else { return entry }
        return await resolver.resolve(entry, into: GlossLanguage(locale: locale))
    }
}
