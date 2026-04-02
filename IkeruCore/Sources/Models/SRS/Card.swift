import Foundation
import SwiftData

/// A learning card representing a single item to study (kanji, vocabulary, grammar, or listening).
/// Uses SwiftData @Model for persistence with FSRS scheduling state.
@Model
public final class Card {

    /// Unique identifier for the card
    public var id: UUID

    /// The front face content (question/prompt)
    public var front: String

    /// The back face content (answer)
    public var back: String

    /// Raw value storage for CardType (used in SwiftData predicates).
    public var typeRawValue: String

    /// The type of learning material this card represents.
    public var type: CardType {
        get { CardType(rawValue: typeRawValue) ?? .kanji }
        set { typeRawValue = newValue.rawValue }
    }

    /// FSRS scheduling state stored as a Codable struct
    public var fsrsState: FSRSState

    /// Ease factor for scheduling (default 2.5)
    public var easeFactor: Double

    /// Current review interval in days
    public var interval: Int

    /// Date when the card is next due for review
    public var dueDate: Date

    /// Number of times the card has lapsed (been forgotten)
    public var lapseCount: Int

    /// Whether this card is flagged as a leech (frequently forgotten)
    public var leechFlag: Bool

    /// The user profile that owns this card
    public var profile: UserProfile?

    /// All review logs for this card
    @Relationship(deleteRule: .cascade, inverse: \ReviewLog.card)
    public var reviewLogs: [ReviewLog]?

    public init(
        front: String,
        back: String,
        type: CardType,
        fsrsState: FSRSState = FSRSState(),
        easeFactor: Double = 2.5,
        interval: Int = 0,
        dueDate: Date = Date(),
        lapseCount: Int = 0,
        leechFlag: Bool = false
    ) {
        self.id = UUID()
        self.front = front
        self.back = back
        self.typeRawValue = type.rawValue
        self.fsrsState = fsrsState
        self.easeFactor = easeFactor
        self.interval = interval
        self.dueDate = dueDate
        self.lapseCount = lapseCount
        self.leechFlag = leechFlag
        self.reviewLogs = []
    }
}
