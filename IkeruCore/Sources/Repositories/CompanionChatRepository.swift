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
