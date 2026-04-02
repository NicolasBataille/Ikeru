import Foundation
import SwiftData

/// A log entry recording a single review event for a card.
/// Tracks the grade given, response time, and timestamp.
@Model
public final class ReviewLog {

    /// Unique identifier for this review log entry
    public var id: UUID

    /// Timestamp when the review occurred
    public var timestamp: Date

    /// The card that was reviewed
    public var card: Card?

    /// Raw value storage for Grade (used in SwiftData predicates).
    public var gradeRawValue: Int

    /// The grade given during this review
    public var grade: Grade {
        get { Grade(rawValue: gradeRawValue) ?? .good }
        set { gradeRawValue = newValue.rawValue }
    }

    /// Response time in milliseconds
    public var responseTimeMs: Int

    public init(
        card: Card,
        grade: Grade,
        responseTimeMs: Int,
        timestamp: Date = Date()
    ) {
        self.id = UUID()
        self.timestamp = timestamp
        self.card = card
        self.gradeRawValue = grade.rawValue
        self.responseTimeMs = responseTimeMs
    }
}
