import Foundation

// MARK: - GlossLanguage

/// La langue dans laquelle une glose doit être LUE — pas celle dans laquelle
/// elle a été capturée (OBS2-041 / P1-5).
public enum GlossLanguage: Sendable, Equatable {
    case french
    case english

    /// Miroir de `AppLocale` : seul le français est distingué, tout le reste
    /// est anglais — comme `ConversationService.isFrench`.
    public init(locale: Locale) {
        self = locale.language.languageCode?.identifier == "fr" ? .french : .english
    }
}

// MARK: - GlossResolver

/// Résout le sens d'un mot du dictionnaire personnel dans la langue de
/// l'interface, AU MOMENT DE L'AFFICHAGE.
///
/// Le défaut (OBS2-041) : à l'import, l'app choisissait la glose française
/// avec repli anglais et STOCKAIT UNE SEULE CHAÎNE ; c'est ce texte figé que
/// chaque surface réaffichait ensuite, quelle que soit la langue choisie.
/// Or le dictionnaire embarqué porte pour chaque entrée la glose française ET
/// l'anglaise : l'information existe, c'est l'enregistrement qui la jetait.
///
/// Règle : une glose n'est re-résolue que si le sens stocké est une glose
/// CAPTURÉE — égale, au caractère près, à l'une des gloses que le
/// dictionnaire propose pour ce mot (française, anglaise, ou anglaise
/// étiquetée « EN — »). Un sens que l'apprenant a écrit ou modifié lui-même
/// n'est jamais réécrit : recroiser un mot n'autorise pas à réécrire ce que
/// l'apprenant en a dit. Sans entrée de dictionnaire, le sens stocké reste.
public struct GlossResolver: Sendable {

    /// L'étiquette de repli anglais posée à l'import — la même constante que
    /// `TextImportViewModel.englishLabelPrefix`, rapatriée ici pour que la
    /// capture et la résolution parlent de la même chose.
    public static let englishLabelPrefix = "EN — "

    public typealias Lookup = @Sendable (Set<String>) async -> [String: [DictionaryEntry]]

    private let lookup: Lookup

    public init(dictionary: DictionaryRepository) {
        self.lookup = { forms in await dictionary.entries(forForms: forms) }
    }

    /// Injection directe, pour les tests et les appelants sans dictionnaire.
    public init(lookup: @escaping Lookup) {
        self.lookup = lookup
    }

    // MARK: Capture

    /// La glose à STOCKER à l'import, dans la langue de l'interface. En
    /// français : la française, sinon l'anglaise étiquetée ; en anglais :
    /// l'anglaise nue.
    public static func gloss(for entry: DictionaryEntry, in language: GlossLanguage) -> String {
        switch language {
        case .french:
            if let french = entry.glossFR, !french.isEmpty { return french }
            return englishLabelPrefix + entry.glossEN
        case .english:
            return entry.glossEN
        }
    }

    /// Vrai si `meaning` est l'une des gloses que le dictionnaire aurait
    /// écrites pour l'une de ces entrées — donc capturée, pas rédigée.
    public static func isCaptured(_ meaning: String, from candidates: [DictionaryEntry]) -> Bool {
        candidates.contains { entry in
            meaning == entry.glossEN
                || meaning == englishLabelPrefix + entry.glossEN
                || (entry.glossFR.map { !$0.isEmpty && meaning == $0 } ?? false)
        }
    }

    // MARK: Resolution

    /// Les mêmes entrées, le sens re-résolu dans `language` quand il était
    /// capturé. L'ordre est gardé ; rien n'est écrit.
    public func resolve(_ entries: [VocabularyEntryDTO], into language: GlossLanguage) async -> [VocabularyEntryDTO] {
        guard !entries.isEmpty else { return entries }
        let forms = Set(entries.map(\.word))
        let table = await lookup(forms)
        return entries.map { entry in
            let candidates = table[entry.word] ?? []
            guard !candidates.isEmpty, Self.isCaptured(entry.meaning, from: candidates) else { return entry }
            let best = candidates.first { $0.reading == entry.reading } ?? candidates[0]
            let resolved = Self.gloss(for: best, in: language)
            return resolved == entry.meaning ? entry : entry.replacingMeaning(resolved)
        }
    }

    /// Une seule entrée — même règle.
    public func resolve(_ entry: VocabularyEntryDTO, into language: GlossLanguage) async -> VocabularyEntryDTO {
        await resolve([entry], into: language).first ?? entry
    }
}

public extension VocabularyEntryDTO {
    /// La même entrée avec un autre sens — pour l'affichage, jamais pour l'écriture.
    func replacingMeaning(_ meaning: String) -> VocabularyEntryDTO {
        VocabularyEntryDTO(
            id: id, word: word, reading: reading, meaning: meaning, jlptLevel: jlptLevel,
            fsrsState: fsrsState, easeFactor: easeFactor, interval: interval, dueDate: dueDate,
            lapseCount: lapseCount, isInDictionary: isInDictionary, createdAt: createdAt,
            encounterCount: encounterCount
        )
    }
}
