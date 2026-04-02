import Foundation

/// Configuration input for adaptive session composition.
/// All properties are value types — the config is a pure data snapshot.
public struct SessionConfig: Sendable, Equatable {

    /// Available time in minutes for this session.
    public let availableTimeMinutes: Int

    /// Whether audio playback is unavailable (e.g., volume muted).
    /// When true, listening and speaking exercises are excluded.
    public let isSilentMode: Bool

    /// Current skill balance ratios from recent history.
    /// Keys are SkillType, values are 0.0-1.0 ratios summing to ~1.0.
    public let currentSkillBalances: [SkillType: Double]

    /// Preferred session intensity (reserved for future use).
    public let preferredIntensity: SessionIntensity

    public init(
        availableTimeMinutes: Int = 20,
        isSilentMode: Bool = false,
        currentSkillBalances: [SkillType: Double] = [:],
        preferredIntensity: SessionIntensity = .normal
    ) {
        self.availableTimeMinutes = availableTimeMinutes
        self.isSilentMode = isSilentMode
        self.currentSkillBalances = currentSkillBalances
        self.preferredIntensity = preferredIntensity
    }
}

/// Session intensity level (reserved for future use).
public enum SessionIntensity: String, Codable, Sendable, Equatable {
    case light
    case normal
    case intense
}
