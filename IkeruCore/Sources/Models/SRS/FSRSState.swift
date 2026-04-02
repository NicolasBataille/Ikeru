import Foundation

/// Lightweight Codable struct representing the FSRS scheduling state for a card.
/// Stored as a transformable property within the Card model.
/// Based on the DSR (Difficulty, Stability, Retrievability) model.
public struct FSRSState: Codable, Equatable, Sendable {

    /// Current difficulty level of the card (higher = harder)
    public let difficulty: Double

    /// Expected time (in days) for retrievability to drop to 90%
    public let stability: Double

    /// Total number of successful reviews
    public let reps: Int

    /// Total number of lapses (failures/resets)
    public let lapses: Int

    /// Timestamp of the last review, nil if never reviewed
    public let lastReview: Date?

    public init(
        difficulty: Double = 0,
        stability: Double = 0,
        reps: Int = 0,
        lapses: Int = 0,
        lastReview: Date? = nil
    ) {
        self.difficulty = difficulty
        self.stability = stability
        self.reps = reps
        self.lapses = lapses
        self.lastReview = lastReview
    }
}
