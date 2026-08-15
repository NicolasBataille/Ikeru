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

    /// Fetches all profiles and selects the active one from persisted id.
    /// Falls back to the oldest profile on cold launch and persists that choice.
    public func loadProfile() {
        // Tombstoned profiles are excluded everywhere: they must not appear in
        // the switcher, must not be re-selectable, and must not count towards
        // `deleteProfile`'s "never delete the last profile" guard.
        let descriptor = FetchDescriptor<UserProfile>(
            predicate: #Predicate { $0.deletedAt == nil },
            sortBy: [SortDescriptor(\.createdAt, order: .forward)]
        )
        let profiles = (try? modelContext.fetch(descriptor)) ?? []
        allProfiles = profiles

        if let activeID = ActiveProfileResolver.activeProfileID(),
           let active = profiles.first(where: { $0.id == activeID }) {
            currentProfile = active
        } else if let first = profiles.first {
            currentProfile = first
            ActiveProfileResolver.setActiveProfileID(first.id)
        } else {
            currentProfile = nil
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
            allProfiles.append(profile)
            ActiveProfileResolver.setActiveProfileID(profile.id)
            // New active profile: the cached display mode in MainTabView
            // must be re-read from the (now-different) active profile's
            // key, or the brand-new profile inherits whatever mode the
            // previously-active profile was showing. See the matching
            // comment in `switchProfile`.
            NotificationCenter.default.post(name: .displayModeDidChange, object: nil)
            Logger.ui.info("Created user profile: \(trimmedName)")
        } catch {
            Logger.ui.error("Failed to save user profile: \(error)")
        }
    }

    // MARK: - Profile Switching

    /// Switches to a different profile and persists the new active id.
    /// - Parameter profile: The profile to switch to.
    public func switchProfile(to profile: UserProfile) {
        currentProfile = profile
        ActiveProfileResolver.setActiveProfileID(profile.id)
        NotificationCenter.default.post(name: .ikeruActiveProfileDidChange, object: profile.id)
        // The display mode (Tatami/Beginner) is stored per-profile
        // (UserDefaultsDisplayModePreferenceRepository keys on the active
        // profile id), but MainTabView caches the resolved mode in a
        // `@State` fed by the repository's CurrentValueSubject — that
        // subject only re-emits on an explicit `repo.set(...)`, never on a
        // profile switch. Without this notification the newly-active
        // profile's mode never gets re-read, and the UI keeps showing
        // whichever mode the *previous* profile was in (the Tatami-leak
        // bug). `.displayModeDidChange` already exists for exactly this
        // "mode changed out from under the cached value" case (onboarding's
        // placement step posts it too) — MainTabView already listens.
        NotificationCenter.default.post(name: .displayModeDidChange, object: nil)
        Logger.ui.info("Switched to profile: \(profile.displayName)")
    }

    /// Soft-deletes a profile: stamps `deletedAt`/`updatedAt` on the profile
    /// and, **by hand**, on everything the old hard delete used to cascade to.
    ///
    /// The cascade is manual now and that is the whole subtlety of this
    /// method. `UserProfile` declares `@Relationship(deleteRule: .cascade)`
    /// for `cards` and `rpgState`, and `Card` declares one for `reviewLogs` —
    /// but SwiftData only runs a delete rule on a real
    /// `modelContext.delete(_:)`. Stamping `deletedAt` on the profile alone
    /// would leave its cards, review logs and RPG state fully live: still
    /// pushed by `SyncModelActor`, still counted by anything that fetches
    /// `Card`/`ReviewLog` directly rather than through the profile. So this
    /// walks the same graph the delete rule used to walk, plus
    /// `ExerciseOutcomeLog` (scoped by a scalar `profileID`, never cascaded
    /// even before).
    ///
    /// Visible behaviour is unchanged: the profile disappears from the
    /// switcher, its data stops counting, and now it also stays gone after a
    /// pull-cursor reset instead of being re-inserted from the server.
    ///
    /// Deleting the *last* remaining profile is refused: this app has no
    /// signed-out state, and driving the user back to onboarding after a
    /// same-screen delete would require `IkeruApp`'s root `showOnboarding`
    /// flag to re-open — state this view model has no reach into. The UI
    /// (`SettingsView`) never offers a delete affordance while only one
    /// profile exists, so this guard should never actually fire from a
    /// live tap; it exists as a safety net if that invariant is ever
    /// violated. See CLAUDE.md-adjacent task notes for the follow-up needed
    /// to support "delete your only profile → back to onboarding".
    ///
    /// - Parameter profile: The profile to delete.
    public func deleteProfile(_ profile: UserProfile) {
        guard allProfiles.count > 1 else {
            Logger.ui.warning("Cannot delete last remaining profile")
            return
        }

        let wasActive = currentProfile?.id == profile.id

        // NOTE (data-model gap, not fixed here — out of this task's file
        // perimeter): `VocabularyEntry`/`VocabularyEncounter` (the "personal
        // dictionary") carry no `profileID` and no relationship back to
        // `UserProfile` at all — they are a single global store shared by
        // every profile on the device. Deleting a profile therefore cannot
        // delete "its" dictionary, because the data model has no concept of
        // per-profile ownership for it. `DeleteProfileSheet`'s summary
        // correctly does NOT claim to erase dictionary entries. Making the
        // dictionary genuinely per-profile needs a schema migration
        // (IkeruSchemaV3) — flagging for a follow-up task.
        //
        // The SwiftData half of the cascade — cards, their review logs, the
        // RPG state, and the scalar-scoped ExerciseOutcomeLog rows — lives in
        // `ProfileDeletion.tombstoneGraph` so it can actually be exercised by
        // a test (see that function's doc comment: this file's own test suite
        // cannot be run today). It does not save; the single `save()` below
        // commits the whole cascade atomically.
        let deletedID = profile.id
        ProfileDeletion.tombstoneGraph(of: profile, in: modelContext)

        // Same reasoning for the per-profile UserDefaults onboarding flags
        // (swipe tutorial, first-session daily-term prompt) — they're keyed by
        // profile id and would otherwise linger forever.
        OnboardingFlags.clearAll(profileID: deletedID)

        // Same reasoning again for the competency-booklet weekly-delta
        // baseline (chantier #45h): also UserDefaults-backed and keyed by
        // profile id (see `MasteryBookSnapshotStore`), so it doesn't cascade
        // with the SwiftData delete below and would otherwise linger forever.
        MasteryBookSnapshotStore.clear(profileID: deletedID)

        do {
            try modelContext.save()
            allProfiles.removeAll { $0.id == profile.id }
            if wasActive, let next = allProfiles.first {
                currentProfile = next
                ActiveProfileResolver.setActiveProfileID(next.id)
                NotificationCenter.default.post(name: .ikeruActiveProfileDidChange, object: next.id)
                // Active profile changed as a side effect of the delete —
                // same cached-display-mode staleness as `switchProfile`.
                NotificationCenter.default.post(name: .displayModeDidChange, object: nil)
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

    /// Updates the FSRS desired-retention target for the current profile.
    /// Clamped to `FSRSService.desiredRetentionRange` (0.8...0.95) — matches
    /// the read side in `CardModelActor.gradeCard`.
    /// - Parameter newValue: The new target retention rate.
    public func updateDesiredRetention(_ newValue: Double) {
        guard let profile = currentProfile else {
            Logger.ui.warning("No profile to update desired retention")
            return
        }

        let clamped = min(
            max(newValue, FSRSService.desiredRetentionRange.lowerBound),
            FSRSService.desiredRetentionRange.upperBound
        )
        let current = profile.settings
        profile.settings = ProfileSettings(
            desiredRetention: clamped,
            dailyNewCardLimit: current.dailyNewCardLimit,
            dailyReviewLimit: current.dailyReviewLimit,
            reviewReminderEnabled: current.reviewReminderEnabled,
            reviewReminderHour: current.reviewReminderHour,
            weeklyCheckInEnabled: current.weeklyCheckInEnabled,
            weeklyCheckInDay: current.weeklyCheckInDay,
            weeklyCheckInHour: current.weeklyCheckInHour
        )

        do {
            try modelContext.save()
            Logger.ui.info("Updated desired retention to: \(clamped)")
        } catch {
            Logger.ui.error("Failed to save desired retention update: \(error)")
        }
    }
}

// MARK: - Notifications

extension Notification.Name {
    /// Posted when the active profile id changes. Observers should reload
    /// per-profile state (RPG, cards, home). Object is the new UUID.
    public static let ikeruActiveProfileDidChange = Notification.Name("ikeru.activeProfileDidChange")
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
