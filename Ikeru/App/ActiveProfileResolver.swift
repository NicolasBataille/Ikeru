import Foundation
import SwiftData
import IkeruCore
import os

/// Single source of truth for "which profile is currently active."
/// The id is persisted in UserDefaults so it survives cold launches, and every
/// per-profile fetch (cards, RPG state) goes through the resolver.
///
/// Use cases:
/// - Cold launch: load active profile from UserDefaults, fall back to first profile
///   if unset; persist the fallback so subsequent launches are stable.
/// - Profile switch: write the new id; next fetch returns that profile's data.
/// - Profile delete: if the deleted profile was active, caller must pick a new
///   one and call `setActiveProfileID(_:)`.
enum ActiveProfileResolver {

    /// UserDefaults key storing the active profile's UUID string.
    static let activeProfileIDKey = "ikeru.activeProfileID"

    /// Reads the persisted active profile id, if any.
    static func activeProfileID() -> UUID? {
        guard
            let raw = UserDefaults.standard.string(forKey: activeProfileIDKey),
            !raw.isEmpty,
            let id = UUID(uuidString: raw)
        else { return nil }
        return id
    }

    /// Persists the active profile id. Passing nil clears it.
    static func setActiveProfileID(_ id: UUID?) {
        UserDefaults.standard.set(id?.uuidString ?? "", forKey: activeProfileIDKey)
        Logger.rpg.info("Active profile id set to: \(id?.uuidString ?? "(nil)")")
    }

    /// Resolves the active `UserProfile` in the given context.
    /// If no id is persisted, falls back to the first profile (by createdAt) and
    /// persists that choice so the next call is stable.
    static func fetchActiveProfile(in context: ModelContext) -> UserProfile? {
        if let id = activeProfileID() {
            let predicate = #Predicate<UserProfile> { $0.id == id }
            var descriptor = FetchDescriptor<UserProfile>(predicate: predicate)
            descriptor.fetchLimit = 1
            if let profile = (try? context.fetch(descriptor))?.first {
                return profile
            }
        }
        // Fallback: oldest profile, persist its id.
        var descriptor = FetchDescriptor<UserProfile>(
            sortBy: [SortDescriptor(\.createdAt, order: .forward)]
        )
        descriptor.fetchLimit = 1
        guard let profile = (try? context.fetch(descriptor))?.first else {
            return nil
        }
        setActiveProfileID(profile.id)
        return profile
    }

    /// Resolves the RPG state for the active profile. Lazily creates one
    /// (attached to the profile) if the profile was created before RPGState
    /// was introduced or the relation is nil for any reason.
    static func fetchActiveRPGState(in context: ModelContext) -> RPGState? {
        guard let profile = fetchActiveProfile(in: context) else { return nil }
        if let existing = profile.rpgState { return existing }
        let newState = RPGState()
        newState.profile = profile
        profile.rpgState = newState
        context.insert(newState)
        do {
            try context.save()
            Logger.rpg.info("Created missing RPG state for profile: \(profile.displayName)")
        } catch {
            Logger.rpg.error("Failed to persist new RPG state: \(error.localizedDescription)")
        }
        return newState
    }
}
