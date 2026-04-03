import Foundation
import SwiftData

/// Cached AI-generated mnemonic for a kanji character.
/// Persisted via SwiftData to avoid redundant AI generation calls.
@Model
public final class MnemonicCache {

    /// Unique identifier for this cache entry.
    public var id: UUID

    /// The kanji character this mnemonic is for (e.g., "日").
    /// Unique constraint prevents duplicate cache entries from concurrent generation.
    @Attribute(.unique) public var character: String

    /// The generated mnemonic text.
    public var mnemonic: String

    /// When this mnemonic was generated.
    public var generatedAt: Date

    /// Which AI tier generated this mnemonic (stored as raw string for SwiftData compatibility).
    public var tierUsed: String

    public init(character: String, mnemonic: String, tierUsed: String) {
        self.id = UUID()
        self.character = character
        self.mnemonic = mnemonic
        self.generatedAt = Date()
        self.tierUsed = tierUsed
    }
}
