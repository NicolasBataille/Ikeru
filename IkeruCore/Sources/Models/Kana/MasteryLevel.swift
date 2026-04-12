import Foundation

/// Five-level mastery scale derived from FSRS state.
public enum MasteryLevel: Int, Sendable, CaseIterable, Codable {
    case new = 0
    case learning = 1
    case familiar = 2
    case mastered = 3
    case anchored = 4

    public var emoji: String {
        switch self {
        case .new: return "🌱"
        case .learning: return "🌾"
        case .familiar: return "🌿"
        case .mastered: return "🌳"
        case .anchored: return "⭐"
        }
    }

    public var label: String {
        switch self {
        case .new: return "Nouveau"
        case .learning: return "En apprentissage"
        case .familiar: return "Familier"
        case .mastered: return "Maîtrisé"
        case .anchored: return "Ancré"
        }
    }

    /// Derive a mastery level from an FSRS state.
    ///
    /// Rules:
    /// - `reps == 0` → `.new`
    /// - `stability < 1.0` OR a recent lapse (within 2 days) → `.learning`
    /// - `stability < 7.0` → `.familiar`
    /// - `stability < 60.0` → `.mastered`
    /// - `stability >= 60.0` → `.anchored`
    public static func from(fsrsState state: FSRSState, now: Date = Date()) -> MasteryLevel {
        if state.reps == 0 {
            return .new
        }

        let hasRecentLapse: Bool = {
            guard state.lapses > 0, let last = state.lastReview else { return false }
            return now.timeIntervalSince(last) < 2 * 86_400
        }()

        if state.stability < 1.0 || hasRecentLapse {
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
