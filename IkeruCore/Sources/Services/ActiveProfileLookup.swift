import Foundation
import SwiftData

/// The one way Core code resolves « the active profile » from a `ModelContext`.
///
/// Three copies of this logic used to live as private helpers in
/// `CardModelActor` and `VocabularyModelActor` (and the app layer has its own
/// `ActiveProfileResolver`). V6 added two more readers — `OwnershipAdoption`
/// and the pull actor — so the rule now lives once, here, and the actors call
/// it.
///
/// The rule: the profile whose id is stored under
/// `UserProfile.activeProfileIDDefaultsKey`, if it exists and is not
/// tombstoned; otherwise the **oldest live** profile. The fallback's tombstone
/// filter is load-bearing: without it, deleting the active profile resolved
/// straight back to the deleted one, and its cards kept driving the app.
public enum ActiveProfileLookup {

    /// The UserDefaults-backed active profile id, or `nil` when unset.
    public static func activeProfileID() -> UUID? {
        guard
            let raw = UserDefaults.standard.string(forKey: UserProfile.activeProfileIDDefaultsKey),
            !raw.isEmpty,
            let id = UUID(uuidString: raw)
        else { return nil }
        return id
    }

    /// The active profile, or the oldest live profile as a fallback, or `nil`
    /// when the store holds no live profile at all.
    public static func resolve(in context: ModelContext) -> UserProfile? {
        if let id = activeProfileID() {
            let predicate = #Predicate<UserProfile> { $0.id == id && $0.deletedAt == nil }
            var descriptor = FetchDescriptor<UserProfile>(predicate: predicate)
            descriptor.fetchLimit = 1
            if let profile = (try? context.fetch(descriptor))?.first {
                return profile
            }
        }
        var descriptor = FetchDescriptor<UserProfile>(
            predicate: #Predicate { $0.deletedAt == nil },
            sortBy: [SortDescriptor(\.createdAt, order: .forward)]
        )
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first
    }
}
