import Foundation

/// An RPG attribute that reflects a dimension of the learner's skill.
/// Attributes unlock at specific level thresholds and grow with mastery.
public struct RPGAttribute: Codable, Sendable, Equatable, Identifiable {

    public let id: String

    /// Display name (e.g., "Reading Mastery", "Listening Focus").
    public let name: String

    /// SF Symbol icon name.
    public let iconName: String

    /// Current attribute value (0-100 scale).
    public let value: Int

    /// The level at which this attribute unlocks.
    public let unlockLevel: Int

    /// Short description of what this attribute represents.
    public let description: String

    public init(
        id: String,
        name: String,
        iconName: String,
        value: Int = 0,
        unlockLevel: Int,
        description: String
    ) {
        self.id = id
        self.name = name
        self.iconName = iconName
        self.value = value
        self.unlockLevel = unlockLevel
        self.description = description
    }

    /// Returns a new attribute with an updated value.
    public func withValue(_ newValue: Int) -> RPGAttribute {
        RPGAttribute(
            id: id,
            name: name,
            iconName: iconName,
            value: min(100, max(0, newValue)),
            unlockLevel: unlockLevel,
            description: description
        )
    }
}

// MARK: - Predefined Attributes

extension RPGAttribute {

    /// All predefined RPG attributes with their unlock levels.
    public static let allPredefined: [RPGAttribute] = [
        RPGAttribute(
            id: "reading",
            name: "Reading",
            iconName: "book.fill",
            unlockLevel: 1,
            description: "Kanji recognition and reading comprehension"
        ),
        RPGAttribute(
            id: "writing",
            name: "Writing",
            iconName: "pencil.line",
            unlockLevel: 1,
            description: "Stroke order and handwriting accuracy"
        ),
        RPGAttribute(
            id: "listening",
            name: "Listening",
            iconName: "ear.fill",
            unlockLevel: 3,
            description: "Audio comprehension and pitch accent"
        ),
        RPGAttribute(
            id: "speaking",
            name: "Speaking",
            iconName: "waveform",
            unlockLevel: 3,
            description: "Pronunciation and shadowing fluency"
        ),
        RPGAttribute(
            id: "grammar",
            name: "Grammar",
            iconName: "text.book.closed.fill",
            unlockLevel: 5,
            description: "Sentence construction and grammar patterns"
        ),
        RPGAttribute(
            id: "vocabulary",
            name: "Vocabulary",
            iconName: "character.book.closed.fill",
            unlockLevel: 5,
            description: "Word knowledge breadth and depth"
        ),
        RPGAttribute(
            id: "culture",
            name: "Culture",
            iconName: "globe.asia.australia.fill",
            unlockLevel: 10,
            description: "Cultural context and nuance understanding"
        ),
        RPGAttribute(
            id: "intuition",
            name: "Intuition",
            iconName: "sparkles",
            unlockLevel: 15,
            description: "Pattern recognition and language sense"
        ),
    ]
}
