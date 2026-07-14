import Foundation

/// Configuration input for adaptive session composition.
/// All properties are value types — the config is a pure data snapshot.
public struct SessionConfig: Sendable, Equatable {

    /// Available time in minutes for this session.
    public let availableTimeMinutes: Int

    /// Current skill balance ratios from recent history.
    /// Keys are SkillType, values are 0.0-1.0 ratios summing to ~1.0.
    public let currentSkillBalances: [SkillType: Double]

    /// Preferred session intensity (reserved for future use).
    public let preferredIntensity: SessionIntensity

    public init(
        availableTimeMinutes: Int = 20,
        currentSkillBalances: [SkillType: Double] = [:],
        preferredIntensity: SessionIntensity = .normal
    ) {
        self.availableTimeMinutes = availableTimeMinutes
        self.currentSkillBalances = currentSkillBalances
        self.preferredIntensity = preferredIntensity
    }
}

// Removed (remediation 7.9): `isSilentMode` used to exclude listening/speaking
// exercises when the volume was 0. It was fed by `AudioService.isSilentMode`,
// which checked `outputVolume` — the volume slider, not the physical mute
// switch — and TTS playback runs in `.playback` category, which ignores the
// mute switch regardless. The flag gave false confidence that audio-dependent
// exercises would actually be silenced, so it — and the exclusion logic in
// `PlannerService.availableSkills()` that read it — has been removed rather
// than wired to a real signal.

/// Session intensity level (reserved for future use).
public enum SessionIntensity: String, Codable, Sendable, Equatable {
    case light
    case normal
    case intense
}
