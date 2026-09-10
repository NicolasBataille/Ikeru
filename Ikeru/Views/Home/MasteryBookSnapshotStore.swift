import Foundation
import IkeruCore

// MARK: - MasteryBookSnapshotStore
//
// Persists a weekly baseline of `MasteryBookCounts` per profile, purely so
// Home can show "cette semaine, N sont passés en familier ou mieux" without
// any SwiftData schema change (this work item does not own the schema —
// see CLAUDE.md's "un seul agent touche au schéma" rule). UserDefaults-
// backed, same per-profile-key pattern as `OnboardingFlags`.
//
// Design (fixed 2026-08-13, chantier #45f): reading and rolling the
// baseline used to happen at the SAME threshold in the SAME
// pass (`priorSnapshot` required age >= 6 days, then `recordIfStale` rolled
// forward at that identical 6-day mark on the very load that just diffed
// against it). That made the "+N cette semaine" badge appear on exactly one
// Home load per week, then vanish for the next six days. The two concerns
// are now split:
//   - `priorSnapshot` compares against WHATEVER baseline is stored, no
//     matter its age, so the delta stays visible continuously through the
//     week as progress accrues (the zero-delta case is already masked by
//     `CompetencyBookCard`, so a same-day comparison reads as "no badge",
//     not a fabricated "+0").
//   - `recordIfStale` only rolls the baseline forward once it's at least
//     `minAge` old (default 7 days — a full week), so the comparison window
//     doesn't drift forward on every Home load.
// The first time a profile is seen there is no baseline yet, so the delta
// is nil until the first `recordIfStale` call seeds one.

enum MasteryBookSnapshotStore {

    private struct StoredSnapshot: Codable {
        let date: Date
        let counts: MasteryBookCounts
    }

    private static func key(_ profileID: UUID) -> String {
        "ikeru.masteryBook.snapshot.\(profileID.uuidString)"
    }

    /// Returns the stored baseline if one exists, regardless of its age.
    /// Returns nil only when no baseline was ever recorded for this profile
    /// (e.g. its first-ever Home load). Age-gating the *rollover* — not the
    /// read — is `recordIfStale`'s job; see this type's doc comment.
    static func priorSnapshot(profileID: UUID) -> MasteryBookCounts? {
        guard
            let data = UserDefaults.standard.data(forKey: key(profileID)),
            let stored = try? JSONDecoder().decode(StoredSnapshot.self, from: data)
        else { return nil }
        return stored.counts
    }

    /// Records `counts` as the new baseline, but ONLY if the current
    /// baseline is missing or already stale (`minAge` or older, default a
    /// full week) — a fresh baseline is left untouched so the comparison
    /// window stays a full week instead of dragging forward on every Home
    /// load.
    static func recordIfStale(
        profileID: UUID,
        counts: MasteryBookCounts,
        minAge: TimeInterval = 7 * 86_400,
        now: Date = Date()
    ) {
        if let data = UserDefaults.standard.data(forKey: key(profileID)),
           let stored = try? JSONDecoder().decode(StoredSnapshot.self, from: data),
           now.timeIntervalSince(stored.date) < minAge {
            return
        }
        let stored = StoredSnapshot(date: now, counts: counts)
        guard let data = try? JSONEncoder().encode(stored) else { return }
        UserDefaults.standard.set(data, forKey: key(profileID))
    }

    /// Removes the stored baseline for a deleted profile. Called from
    /// `ProfileViewModel.deleteProfile` alongside `OnboardingFlags.clearAll`
    /// and the `ExerciseOutcomeLog` cleanup (chantier #45h, 2026-08-13) —
    /// the key is scoped per profile UUID (see `key(_:)`), so skipping this
    /// would leak one UserDefaults entry per deleted profile forever.
    static func clear(profileID: UUID) {
        UserDefaults.standard.removeObject(forKey: key(profileID))
    }
}
