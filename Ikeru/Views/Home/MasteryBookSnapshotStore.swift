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
// Design: the baseline only rolls forward once it's at least `minAge` old
// (default ~6 days), so repeated Home loads within the same week keep
// comparing against the SAME baseline instead of drifting day to day. The
// first time a profile is seen, there is no baseline yet — the delta is
// simply unavailable (nil) until a week has passed, which is honest: no
// fabricated "+0" on day one.

enum MasteryBookSnapshotStore {

    private struct StoredSnapshot: Codable {
        let date: Date
        let counts: MasteryBookCounts
    }

    private static func key(_ profileID: UUID) -> String {
        "ikeru.masteryBook.snapshot.\(profileID.uuidString)"
    }

    /// Returns the stored baseline if one exists AND it's old enough to diff
    /// against (`minAge`, default ~6 days). Returns nil otherwise — either no
    /// baseline was ever recorded, or it's too fresh (same week) to compare.
    static func priorSnapshot(
        profileID: UUID,
        minAge: TimeInterval = 6 * 86_400,
        now: Date = Date()
    ) -> MasteryBookCounts? {
        guard
            let data = UserDefaults.standard.data(forKey: key(profileID)),
            let stored = try? JSONDecoder().decode(StoredSnapshot.self, from: data),
            now.timeIntervalSince(stored.date) >= minAge
        else { return nil }
        return stored.counts
    }

    /// Records `counts` as the new baseline, but ONLY if the current
    /// baseline is missing or already stale (`minAge` or older) — a fresh
    /// baseline is left untouched so the comparison window stays a full
    /// week instead of dragging forward on every Home load.
    static func recordIfStale(
        profileID: UUID,
        counts: MasteryBookCounts,
        minAge: TimeInterval = 6 * 86_400,
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

    /// Removes the stored baseline for a deleted profile. NOTE: not yet
    /// wired into profile deletion — `ProfileViewModel.deleteProfile` (which
    /// already cleans up `OnboardingFlags` and `ExerciseOutcomeLog`) is
    /// outside this work item's file perimeter. Left as a documented gap
    /// rather than silently leaking a UserDefaults key per deleted profile.
    static func clear(profileID: UUID) {
        UserDefaults.standard.removeObject(forKey: key(profileID))
    }
}
