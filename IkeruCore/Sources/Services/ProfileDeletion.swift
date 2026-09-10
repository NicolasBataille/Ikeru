import Foundation
import SwiftData

/// The deletion cascade for a `UserProfile`, as a single reusable function.
///
/// ## Why this is not just three lines inside `ProfileViewModel`
///
/// Deleting a profile used to be one `modelContext.delete(profile)`, and
/// SwiftData did the rest: `UserProfile` declares
/// `@Relationship(deleteRule: .cascade)` for `cards` and `rpgState`, and
/// `Card` declares one for `reviewLogs`, so the whole graph went with it.
///
/// Tombstoning does **not** trigger any of that — a delete rule only fires on
/// a real `modelContext.delete(_:)`. Stamping `deletedAt` on the profile alone
/// would leave its cards, their review logs and its RPG state fully live:
/// still pushed by `SyncModelActor`, still visible to every read that queries
/// `Card`/`ReviewLog` directly instead of walking down from the profile. So
/// the cascade has to be walked by hand, and it has to walk *exactly* the same
/// graph the delete rules used to — plus `ExerciseOutcomeLog`, which is scoped
/// by a scalar `profileID` and was never cascaded even before — plus, since
/// `IkeruSchemaV6` (P1-1 / OBS2-051), the profile's dictionary
/// (`VocabularyEntry` and their `VocabularyEncounter`s) and its imported
/// texts (`TextImport`), both scalar-scoped the same way. Before V6 they had no
/// owner and survived every deletion, which the deletion screen had to
/// confess in a « What stays » card; that card is gone with this cascade.
///
/// It lives in `IkeruCore` rather than inline in `ProfileViewModel` for one
/// concrete reason: `IkeruTests/ProfileViewModelTests` cannot currently be
/// executed at all (every `@Test` in that file SIGTRAPs inside SwiftData in
/// the app-hosted test host — a pre-existing failure documented in that file's
/// header, and why CI does not run it). Left in the view model, the riskiest
/// part of the tombstone work would have had no runnable test anywhere. Here
/// it is covered by `SyncPullDivergenceTombstoneTests`.
public enum ProfileDeletion {

    /// Tombstones `profile` and every row the old `.cascade` delete rules
    /// reached, plus its `ExerciseOutcomeLog`, `VocabularyEntry` (with their
    /// encounters) and `TextImport` rows.
    ///
    /// All rows get the **same** instant, and `SoftDeletable.tombstone(at:)`
    /// is idempotent, so a row already deleted earlier keeps its original
    /// deletion time.
    ///
    /// Deliberately does **not** call `context.save()`: the caller owns the
    /// transaction (`ProfileViewModel.deleteProfile` saves once, so the whole
    /// cascade lands atomically or not at all, and can report a single
    /// failure).
    ///
    /// - Parameters:
    ///   - profile: The profile being deleted.
    ///   - context: The context to search for the scalar-scoped
    ///     `ExerciseOutcomeLog` rows in.
    ///   - now: The deletion instant, injected so tests can assert it.
    public static func tombstoneGraph(
        of profile: UserProfile,
        in context: ModelContext,
        at now: Date = Date()
    ) {
        // `ExerciseOutcomeLog` has no relationship to `UserProfile` — only a
        // scalar `profileID` — so it has to be fetched, not traversed.
        let profileID = profile.id
        let outcomeDescriptor = FetchDescriptor<ExerciseOutcomeLog>(
            predicate: #Predicate { $0.profileID == profileID && $0.deletedAt == nil }
        )
        for outcome in (try? context.fetch(outcomeDescriptor)) ?? [] {
            outcome.tombstone(at: now)
        }

        // The dictionary and the imported texts — scalar-scoped like the
        // outcomes, and only owned since V6. An entry's encounters are a
        // relationship, so they are walked, not fetched (same as the cards'
        // review logs below); `VocabularyModelActor.deleteEntry` does the
        // same for a single entry. An import's entries are NOT resolved
        // through `entryIDs` here: they belong to the same profile and are
        // already covered by the entry sweep.
        let entryDescriptor = FetchDescriptor<VocabularyEntry>(
            predicate: #Predicate { $0.profileID == profileID && $0.deletedAt == nil }
        )
        for entry in (try? context.fetch(entryDescriptor)) ?? [] {
            entry.tombstone(at: now)
            for encounter in entry.encounters ?? [] {
                encounter.tombstone(at: now)
            }
        }
        let importDescriptor = FetchDescriptor<TextImport>(
            predicate: #Predicate { $0.profileID == profileID && $0.deletedAt == nil }
        )
        for record in (try? context.fetch(importDescriptor)) ?? [] {
            record.tombstone(at: now)
        }

        // The graph the `.cascade` rules used to walk.
        for card in profile.cards ?? [] {
            card.tombstone(at: now)
            for log in card.reviewLogs ?? [] {
                log.tombstone(at: now)
            }
        }
        profile.rpgState?.tombstone(at: now)
        profile.tombstone(at: now)
    }
}
