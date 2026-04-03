import Foundation
import SwiftData

// MARK: - Message Role

/// Role of a companion chat message.
public enum CompanionMessageRole: String, Codable, Sendable {
    case user
    case companion
    case system
}

// MARK: - CompanionChatMessage

/// A single message in the companion chat, persisted via SwiftData.
@Model
public final class CompanionChatMessage {

    /// Unique identifier for the message.
    public var id: UUID

    /// Who sent the message.
    public var roleRawValue: String

    /// The raw content of the message (may contain inline tags).
    public var content: String

    /// When the message was created.
    public var createdAt: Date

    /// The profile this message belongs to.
    public var profileId: UUID

    // MARK: - Computed

    /// Typed role accessor.
    @Transient
    public var role: CompanionMessageRole {
        CompanionMessageRole(rawValue: roleRawValue) ?? .system
    }

    // MARK: - Init

    public init(
        role: CompanionMessageRole,
        content: String,
        profileId: UUID
    ) {
        self.id = UUID()
        self.roleRawValue = role.rawValue
        self.content = content
        self.createdAt = Date()
        self.profileId = profileId
    }
}
