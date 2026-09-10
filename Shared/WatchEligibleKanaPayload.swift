import Foundation
import IkeruCore

// MARK: - WatchEligibleKanaPayload

/// The set of kana characters the Watch quiz is allowed to draw questions
/// from: the learner's currently chosen kana groups (see the app target's
/// `StudySetStore`) intersected with kana already graded at least once
/// (`CardDTO.fsrsState.reps > 0`).
///
/// Two defects this closes (chantier: "le quiz de la montre interroge sur
/// des kana que l'apprenant n'a pas choisis, et note des cartes qu'il n'a
/// jamais rencontrees"):
///  1. Without this, `WatchQuizViewModel.startSession()` drew from the
///     entire `KanaData.hiragana` catalog regardless of which groups were
///     selected on the phone.
///  2. The P2 presentation phase (see `NewCardPresentationScheduler`) gives
///     a never-graded kana an ungraded encounter before its first real FSRS
///     test, specifically so that first grade measures retention rather
///     than first-encounter noise. The Watch quiz has no presentation
///     phase of its own, so it must never target a `reps == 0` card — doing
///     so would produce exactly the noisy first grade the phase exists to
///     avoid. Restricting the pool to `reps > 0` kana is how the Watch
///     honors that rule without needing its own presentation UI.
///
/// Piggybacks on the SAME `WCSession.updateApplicationContext` call as the
/// RPG-state sync (`WatchSyncPayload`, in `IkeruCore`, sent from
/// `WatchConnectivityManager.sendStateToWatch`): application context keeps
/// only the single latest dictionary a session sent, so a second, separate
/// `updateApplicationContext` call would silently REPLACE the RPG-state
/// context rather than add to it. Instead, this payload's dictionary entry
/// is merged into that same outgoing dictionary under `contextKey`.
/// `WatchSyncPayload`'s synthesized `Codable` decoder ignores unrecognized
/// keys, so both payloads round-trip independently from one merged
/// dictionary without either needing to know about the other's shape.
///
/// Lives in `Shared/` (not `IkeruCore`) for the same reason as
/// `WatchQuizReviewBatch`: it must be registered directly in both the
/// `Ikeru` and `IkeruWatch` Xcode targets' Sources build phases (this
/// project's `project.pbxproj` has no synchronized groups), and staying out
/// of `IkeruCore/Sources` avoids touching that package while another
/// workstream has exclusivity over `IkeruCore/Sources/Models` in parallel.
public struct WatchEligibleKanaPayload: Codable, Sendable, Equatable {

    /// Key this payload's value is merged under inside the shared
    /// applicationContext dictionary. Stored as a bare `[String]` (not a
    /// nested JSON-encoded struct) since application context values must be
    /// property-list types and an array of strings already is one — no
    /// second `JSONSerialization` round trip needed on either side.
    public static let contextKey = "watchEligibleKanaCharacters"

    /// Kana characters (`CardDTO.front`) eligible for the Watch quiz.
    /// Empty is a legitimate, meaningful value (see `fromContext`'s doc) —
    /// not an error case to special-case away.
    public let characters: [String]

    public init(characters: [String]) {
        self.characters = characters
    }

    /// The raw value to store at `contextKey` in an outgoing
    /// applicationContext dictionary.
    public var contextValue: [String] { characters }

    /// Extracts the eligible-kana list from a received applicationContext
    /// dictionary.
    ///
    /// Returns `nil` only when the key is entirely absent — an iPhone build
    /// that predates this chantier, or a context that was never received at
    /// all. Callers MUST treat a `nil` result the same as an explicitly
    /// empty list (zero eligible characters), never as "everything is
    /// eligible": falling back to the full hiragana catalog on a missing
    /// key would silently reintroduce defect (a) this type exists to close.
    public static func fromContext(_ dict: [String: Any]) -> WatchEligibleKanaPayload? {
        guard let characters = dict[contextKey] as? [String] else { return nil }
        return WatchEligibleKanaPayload(characters: characters)
    }

    // MARK: - Pool filtering

    /// Restricts `pool` (typically `KanaData.hiragana`) to the entries whose
    /// `character` appears in `characters`. Pure and shared so the Watch
    /// quiz's own pool-building (`WatchQuizViewModel.eligiblePool`) and this
    /// type's tests exercise the exact same logic, rather than two
    /// hand-written copies that could silently drift apart.
    ///
    /// An empty (or absent — see `fromContext`) `characters` list correctly
    /// yields an empty pool here; callers must not special-case that away.
    public static func filterKanaEntries(
        _ pool: [KanaData.Entry],
        toCharacters characters: [String]
    ) -> [KanaData.Entry] {
        let eligible = Set(characters)
        return pool.filter { eligible.contains($0.character) }
    }
}
