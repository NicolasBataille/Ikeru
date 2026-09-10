import Foundation
import SwiftData
import os

// MARK: - CompanionChatRepository

/// Repository for persisting and retrieving companion chat messages.
public final class CompanionChatRepository: Sendable {

    private let modelContainer: ModelContainer

    public init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
    }

    // MARK: - Fetch

    /// Fetches all messages for a given profile, ordered by creation date.
    @MainActor
    public func messages(for profileId: UUID) -> [CompanionChatMessage] {
        let context = modelContainer.mainContext
        var descriptor = FetchDescriptor<CompanionChatMessage>(
            predicate: #Predicate { $0.profileId == profileId },
            sortBy: [SortDescriptor(\.createdAt, order: .forward)]
        )
        descriptor.fetchLimit = 200

        do {
            return try context.fetch(descriptor)
        } catch {
            Logger.ui.error("Failed to fetch companion messages: \(error)")
            return []
        }
    }

    // MARK: - Save

    /// Saves a new message to the store.
    @MainActor
    public func save(_ message: CompanionChatMessage) {
        let context = modelContainer.mainContext
        context.insert(message)

        do {
            try context.save()
        } catch {
            Logger.ui.error("Failed to save companion message: \(error)")
        }
    }

    // MARK: - Clear

    /// Deletes all messages for a given profile.
    ///
    /// A **hard** delete on purpose, unlike every other learner-data deletion
    /// (which tombstones — see `SoftDeletable`). `CompanionChatMessage` is
    /// neither pushed nor pulled: `SyncPayloadBuilder` builds no row for it
    /// and `SyncModelActor` has no `pushDirtyCompanion*`, both because the
    /// message text is free-form conversation held back for a separate opt-in
    /// that does not exist yet. With nothing on the server there is no
    /// resurrection vector to defend against — and a tombstone would *keep*
    /// the text on the device the learner just asked to clear it from.
    /// Erasing it outright is both simpler and the more private answer.
    ///
    /// If companion chat is ever added to the sync payload, this must become
    /// a tombstone at the same time, or clearing history will silently
    /// un-clear itself on the next pull.
    @MainActor
    public func clearHistory(for profileId: UUID) {
        let context = modelContainer.mainContext

        do {
            try context.delete(
                model: CompanionChatMessage.self,
                where: #Predicate { $0.profileId == profileId }
            )
            try context.save()
            Logger.ui.info("Cleared companion chat history for profile \(profileId)")
        } catch {
            Logger.ui.error("Failed to clear companion chat history: \(error)")
        }
    }
}
