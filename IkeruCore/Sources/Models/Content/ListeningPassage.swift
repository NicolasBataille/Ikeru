import Foundation

/// A listening comprehension passage with transcript and audio reference.
/// This is a plain value type for static content from the SQLite bundle.
public struct ListeningPassage: Sendable, Codable, Identifiable, Equatable {

    /// Unique identifier for the listening passage.
    public let id: Int

    /// JLPT level classification.
    public let jlptLevel: JLPTLevel

    /// Japanese transcript of the passage.
    public let transcript: String

    /// Reference to the audio file (e.g., "n5_listening_001.m4a"). Nil if unavailable.
    public let audioRef: String?

    /// Difficulty rating within the level (1 = easiest).
    public let difficulty: Int

    public init(
        id: Int,
        jlptLevel: JLPTLevel,
        transcript: String,
        audioRef: String?,
        difficulty: Int
    ) {
        self.id = id
        self.jlptLevel = jlptLevel
        self.transcript = transcript
        self.audioRef = audioRef
        self.difficulty = difficulty
    }
}
