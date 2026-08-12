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
    /// - `reps < 2` OR `stability < 1.0` OR a recent lapse (within 2 days) → `.learning`
    /// - `stability < 7.0` → `.familiar`
    /// - `stability < 60.0` → `.mastered`
    /// - `stability >= 60.0` → `.anchored`
    ///
    /// The `reps >= 2` gate keeps a single tap from promoting a card past
    /// `.learning`: one 'Good' press yields stability ≈ 3.13 and one 'Easy'
    /// ≈ 15.47, which would otherwise land at `.familiar` / `.mastered`
    /// immediately and count toward exercise-unlock gates and JLPT readiness.
    public static func from(fsrsState state: FSRSState, now: Date = Date()) -> MasteryLevel {
        if state.reps == 0 {
            return .new
        }

        let hasRecentLapse: Bool = {
            guard state.lapses > 0, let last = state.lastReview else { return false }
            return now.timeIntervalSince(last) < 2 * 86_400
        }()

        if state.reps < 2 || state.stability < 1.0 || hasRecentLapse {
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
