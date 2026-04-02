import Foundation

/// Categorizes available session time into tiers that determine composition strategy.
public enum SessionDuration: Sendable, Equatable {
    /// 2-5 minutes: SRS reviews only, max 10 cards.
    case micro
    /// 10-15 minutes: SRS reviews + one supplementary skill exercise.
    case short
    /// 20-25 minutes: SRS reviews + mixed skill exercises.
    case standard
    /// 30+ minutes: full mixed session with all four skills represented.
    case focused

    /// Determines the appropriate duration tier from available minutes.
    public static func from(minutes: Int) -> SessionDuration {
        switch minutes {
        case ...5: .micro
        case 6...15: .short
        case 16...29: .standard
        default: .focused
        }
    }

    /// Maximum number of SRS cards for this tier.
    public var maxSRSCards: Int {
        switch self {
        case .micro: 10
        case .short: 20
        case .standard: 30
        case .focused: .max
        }
    }

    /// Whether this tier includes non-SRS exercises.
    public var includesSupplementary: Bool {
        switch self {
        case .micro: false
        case .short, .standard, .focused: true
        }
    }

    /// Whether this tier requires all four skills to be represented.
    public var requiresAllSkills: Bool {
        switch self {
        case .micro, .short: false
        case .standard, .focused: true
        }
    }
}
