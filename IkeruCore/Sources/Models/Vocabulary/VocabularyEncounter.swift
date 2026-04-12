import Foundation
import SwiftData

/// A log entry recording where and when a vocabulary word was encountered.
@Model
public final class VocabularyEncounter {

    /// Unique identifier for this encounter.
    public var id: UUID

    /// Timestamp of the encounter.
    public var timestamp: Date

    /// Raw value storage for EncounterSource (used in SwiftData predicates).
    public var sourceRawValue: String

    /// Where in the app the word was encountered.
    public var source: EncounterSource {
        get { EncounterSource(rawValue: sourceRawValue) ?? .sakuraChat }
        set { sourceRawValue = newValue.rawValue }
    }

    /// The sentence or context where the word appeared.
    public var contextSnippet: String

    /// The vocabulary entry this encounter belongs to.
    public var entry: VocabularyEntry?

    public init(
        source: EncounterSource,
        contextSnippet: String,
        entry: VocabularyEntry,
        timestamp: Date = Date()
    ) {
        self.id = UUID()
        self.timestamp = timestamp
        self.sourceRawValue = source.rawValue
        self.contextSnippet = contextSnippet
        self.entry = entry
    }
}
