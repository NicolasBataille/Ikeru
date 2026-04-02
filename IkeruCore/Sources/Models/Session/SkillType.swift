import Foundation

/// The four language learning skills tracked for balanced session composition.
public enum SkillType: String, Codable, CaseIterable, Sendable, Hashable {
    case reading
    case writing
    case listening
    case speaking

    /// Whether this skill is receptive (input-focused) vs productive (output-focused).
    /// Receptive skills are sequenced before productive skills in sessions.
    public var isReceptive: Bool {
        switch self {
        case .reading, .listening: true
        case .writing, .speaking: false
        }
    }

    /// Whether this skill requires audio playback.
    public var requiresAudio: Bool {
        switch self {
        case .listening, .speaking: true
        case .reading, .writing: false
        }
    }

    /// Pedagogical sort order: receptive before productive, reading before listening.
    public var pedagogicalOrder: Int {
        switch self {
        case .reading: 0
        case .listening: 1
        case .writing: 2
        case .speaking: 3
        }
    }
}
