import Foundation

/// Five-level mastery scale derived from FSRS state.
public enum MasteryLevel: Int, Sendable, CaseIterable, Codable {
    case new = 0
    case learning = 1
    case familiar = 2
    case mastered = 3
    case anchored = 4

    /// Tatami-direction glyph for the level. Single-character kanji
    /// (and a stillness mark for `.anchored`) replace the prior emoji
    /// set so cells stay coherent with the wabi visual vocabulary.
    public var glyph: String {
        switch self {
        case .new:       return "\u{521D}"  // 初  — beginning
        case .learning:  return "\u{5B66}"  // 学  — study
        case .familiar:  return "\u{6163}"  // 慣  — familiar
        case .mastered:  return "\u{6975}"  // 極  — mastery
        case .anchored:  return "\u{5FC3}"  // 心  — heart / grounded
        }
    }

    @available(*, deprecated, renamed: "glyph", message: "Tatami direction replaces plant emojis with kanji glyphs.")
    public var emoji: String { glyph }

    /// Localization-catalog **key** for the mastery level, not display text.
    ///
    /// `String(localized:)` inside IkeruCore resolves the wrong bundle and
    /// ignores the app's `AppLocale` override (see CLAUDE.md ›
    /// Localisation), so this deliberately does not return translated text.
    /// Callers in the app layer must render it as
    /// `Text(LocalizedStringKey(level.label))` so the lookup happens against
    /// the app's `Localizable.xcstrings` with the correct locale.
    public var label: String {
        switch self {
        case .new: return "Mastery.New"
        case .learning: return "Mastery.Learning"
        case .familiar: return "Mastery.Familiar"
        case .mastered: return "Mastery.Mastered"
        case .anchored: return "Mastery.Anchored"
        }
    }

    /// Derive a mastery level from an FSRS state.
    ///
    /// Rules:
    /// - `reps == 0` → `.new`
    /// - `reps < 2` OR `stability < 1.0` → `.learning`
    /// - `stability < 7.0` → `.familiar`
    /// - `stability < 60.0` → `.mastered`
    /// - `stability >= 60.0` → `.anchored`
    ///
    /// The `reps >= 2` gate keeps a single tap from promoting a card past
    /// `.learning`: one 'Good' press yields stability ≈ 3.13 and one 'Easy'
    /// ≈ 15.47, which would otherwise land at `.familiar` / `.mastered`
    /// immediately and count toward exercise-unlock gates and JLPT readiness.
    ///
    /// ### Pourquoi il n'y a PAS de règle « rechute récente » (OBS2-024/077/081)
    ///
    /// Une condition supplémentaire rétrogradait en `.learning` toute carte
    /// portant `lapses > 0` dont la dernière révision datait de moins de 48 h.
    /// Elle avait deux défauts, et le second était fatal :
    ///
    /// 1. `lapses` est un compteur **à vie** : une carte ratée une seule fois,
    ///    six mois plus tôt, restait éligible pour toujours.
    /// 2. La fenêtre partait de `lastReview`, qui ne distingue pas une réussite
    ///    d'un échec — donc **chaque révision, y compris réussie, la réarmait**.
    ///    Or les cartes ayant rechuté ont justement l'intervalle le plus court :
    ///    elles reviennent tous les jours ou deux. Pour elles la rétrogradation
    ///    n'était pas transitoire mais **permanente**, et ne se levait que si
    ///    l'apprenant cessait de réviser 48 h. Pour une app dont la thèse est
    ///    « pas de série, pas de pression quotidienne », c'était l'inversion
    ///    exacte du signal.
    ///
    /// Corriger l'intention aurait demandé un champ `lastLapse`, donc une
    /// migration de schéma. **Mesuré avant de la réclamer** (voir les tests) :
    /// FSRS effondre déjà la stabilité de 70 à 95 % sur un échec — 10 → 2,80 ;
    /// 20 → 4,04 ; 50 → 6,31. En dessous d'environ 80 de stabilité, la carte
    /// redescend donc **d'elle-même** sous le palier supérieur, et la règle ne
    /// faisait que répéter une rétrogradation déjà survenue en y ajoutant son
    /// propre défaut. Au-delà de ~100 de stabilité l'échec ne suffit plus à
    /// faire changer de palier — mais c'est exactement la population que le
    /// défaut n'atteignait pas, ces cartes ne revenant que tous les plusieurs
    /// mois. La règle protégeait celles qui n'en avaient pas besoin et abîmait
    /// celles qui revenaient tous les jours.
    ///
    /// Si l'intention doit revenir un jour, la conditionner à la **stabilité**
    /// et non au **temps** — même fichier, toujours aucune migration.
    ///
    /// - Parameter now: **plus lu.** Le palier ne dépend plus de l'horloge
    ///   depuis le retrait ci-dessus. Le paramètre est conservé parce que six
    ///   sites d'appel lui passent déjà l'horloge qu'ils propagent pour
    ///   d'autres calculs ; le retirer transformerait un correctif de quatre
    ///   lignes en une cascade de paramètres devenus inutilisés dans quatre
    ///   fichiers. Il redeviendrait utile si le palier redevenait un jour
    ///   fonction du temps — ce que la note ci-dessus déconseille.
    public static func from(fsrsState state: FSRSState, now: Date = Date()) -> MasteryLevel {
        if state.reps == 0 {
            return .new
        }

        if state.reps < 2 || state.stability < 1.0 {
            return .learning
        }
        if state.stability < 7.0 {
            return .familiar
        }
        if state.stability < 60.0 {
            return .mastered
        }
        return .anchored
    }
}
