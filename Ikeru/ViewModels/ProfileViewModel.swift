import SwiftUI
import SwiftData
import IkeruCore
import os

// MARK: - ProfileViewModel

@MainActor
@Observable
public final class ProfileViewModel {

    // MARK: - Properties

    private let modelContext: ModelContext

    /// The current user profile, if one exists.
    public private(set) var currentProfile: UserProfile?

    /// All available user profiles.
    public private(set) var allProfiles: [UserProfile] = []

    /// Whether a profile exists (used for onboarding gating).
    public var hasProfile: Bool {
        currentProfile != nil
    }

    /// The display name of the current profile.
    public var displayName: String {
        currentProfile?.displayName ?? ""
    }

    // MARK: - Init

    public init(modelContext: ModelContext) {
        self.modelContext = modelContext
        loadProfile()
    }

    // MARK: - Profile Loading

    /// Fetches all profiles and sets the first as current if none is set.
    public func loadProfile() {
        let descriptor = FetchDescriptor<UserProfile>()
        let profiles = (try? modelContext.fetch(descriptor)) ?? []
        allProfiles = profiles
        if currentProfile == nil {
            currentProfile = profiles.first
        }
        Logger.ui.debug("Profiles loaded: \(profiles.count), current: \(self.currentProfile?.displayName ?? "none")")
    }

    // MARK: - Profile Creation

    /// Creates a new UserProfile with the given name and persists it.
    /// - Parameter name: The display name for the new profile.
    public func createProfile(name: String) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            Logger.ui.warning("Attempted to create profile with empty name")
            return
        }

        let profile = UserProfile(displayName: trimmedName)
        modelContext.insert(profile)

        do {
            try modelContext.save()
            currentProfile = profile
            Logger.ui.info("Created user profile: \(trimmedName)")
        } catch {
            Logger.ui.error("Failed to save user profile: \(error)")
        }
    }

    // MARK: - Profile Switching

    /// Switches to a different profile.
    /// - Parameter profile: The profile to switch to.
    public func switchProfile(to profile: UserProfile) {
        currentProfile = profile
        Logger.ui.info("Switched to profile: \(profile.displayName)")
    }

    /// Deletes a profile (only if it's not the last remaining one).
    /// - Parameter profile: The profile to delete.
    public func deleteProfile(_ profile: UserProfile) {
        guard allProfiles.count > 1 else {
            Logger.ui.warning("Cannot delete last remaining profile")
            return
        }

        modelContext.delete(profile)
        do {
            try modelContext.save()
            allProfiles.removeAll { $0.id == profile.id }
            if currentProfile?.id == profile.id {
                currentProfile = allProfiles.first
            }
            Logger.ui.info("Deleted profile: \(profile.displayName)")
        } catch {
            Logger.ui.error("Failed to delete profile: \(error)")
        }
    }

    // MARK: - Profile Update

    /// Updates the display name of the current profile.
    /// - Parameter newName: The new display name.
    public func updateDisplayName(_ newName: String) {
        let trimmedName = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            Logger.ui.warning("Attempted to set empty display name")
            return
        }

        guard let profile = currentProfile else {
            Logger.ui.warning("No profile to update")
            return
        }

        profile.displayName = trimmedName

        do {
            try modelContext.save()
            Logger.ui.info("Updated display name to: \(trimmedName)")
        } catch {
            Logger.ui.error("Failed to save display name update: \(error)")
        }
    }
}

// MARK: - Environment Key

private struct ProfileViewModelKey: EnvironmentKey {
    // Default is a placeholder; IkeruApp injects a real one
    nonisolated(unsafe) static let defaultValue: ProfileViewModel? = nil
}

extension EnvironmentValues {
    public var profileViewModel: ProfileViewModel? {
        get { self[ProfileViewModelKey.self] }
        set { self[ProfileViewModelKey.self] = newValue }
    }
}
