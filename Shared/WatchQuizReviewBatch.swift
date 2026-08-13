import Foundation

// MARK: - WatchQuizReviewBatch

/// A batch of individually-graded kana quiz answers from a single Watch
/// nano-session, transferred to the iPhone via `WCSession.transferUserInfo`
/// so each wrist answer becomes a real `ReviewLog` through the same
/// `CardRepository.gradeCard` the iPhone kana drill and main session use —
/// see chantier #46 ("une revision faite au poignet n'atteint jamais le
/// planificateur").
///
/// Lives in `Shared/` (not `IkeruCore`) because it is registered directly in
/// both the `Ikeru` and `IkeruWatch` Xcode targets' Sources build phases —
/// this project's `project.pbxproj` has no synchronized groups, so every
/// source file must be listed explicitly per target. `IkeruWatch` already
/// links the `IkeruCore` SPM package (its types would be picked up
/// automatically), but this type intentionally stays out of `IkeruCore`
/// during this chantier since another workstream has exclusivity over
/// `IkeruCore/Sources/Models` in parallel — see the chantier notes.
public struct WatchQuizReviewBatch: Codable, Sendable {

    /// Discriminator stored in the encoded dictionary so
    /// `WatchConnectivityManager` can try this format before falling back to
    /// the older aggregate-only `WatchSessionResult` — belt-and-suspenders:
    /// the two structs' required-key sets don't actually overlap today (see
    /// `fromDictionary`'s doc), but an explicit marker keeps that true even
    /// as both evolve independently.
    public static let messageKind = "watchQuizReviewBatch"

    public let kind: String

    /// Stable id for this whole nano-session — the idempotency key.
    /// `transferUserInfo` delivery is guaranteed but not documented as
    /// exactly-once (a relaunch racing delivery, or any future retry logic,
    /// could redeliver the same payload); the iPhone side must dedupe on
    /// this id so a replayed batch never grades the same answers twice.
    public let sessionId: UUID

    /// One entry per question answered in the nano-session, in answer order.
    public let events: [Event]

    /// Total XP this nano-session is worth. Applied once as an aggregate
    /// bump to `RPGState.xp` — a Watch-specific bonus mechanic, unchanged
    /// from before this chantier. NOT awarded per-event via `gradeCard`:
    /// the iPhone kana drill (`KanaDrillViewModel`) awards zero XP for
    /// grading a card at all — XP there is a main-session-only mechanic
    /// (see `SessionRPGPersistence`) — so per-event XP here would create a
    /// *new* inconsistency, not fix the existing one. Documented as an open
    /// question in the chantier notes rather than silently resolved either
    /// way.
    public let xpEarned: Int

    public init(sessionId: UUID = UUID(), events: [Event], xpEarned: Int) {
        self.kind = Self.messageKind
        self.sessionId = sessionId
        self.events = events
        self.xpEarned = xpEarned
    }

    /// A single graded kana quiz question.
    public struct Event: Codable, Sendable {

        /// The kana character that was the correct answer — matches
        /// `CardDTO.front` for the corresponding kana card (kana cards are
        /// `.vocabulary`-typed and identified by `front` membership in the
        /// `KanaGroup` catalog; see `KanaCardRepository`). This is how the
        /// iPhone reception resolves a wrist answer back to a real `Card`
        /// without the Watch ever knowing about `Card`/`CardDTO` — the Watch
        /// quiz pool is the static `KanaData.hiragana` catalog, not
        /// SwiftData-backed.
        public let targetCharacter: String

        /// The character the learner actually chose — the confusable kana,
        /// not the romaji button label, mirroring
        /// `KanaDrillViewModel.submitQuizAnswer` / `ReviewLog.answeredValue`
        /// so a wrist confusion pair (e.g. シ vs ツ) is analyzable exactly
        /// like a phone one. Equal to `targetCharacter` when correct.
        public let answeredCharacter: String

        public let isCorrect: Bool

        /// Time from question shown to answer tapped, in milliseconds — fed
        /// into the same `mapQuizResultToGrade(correct:responseTimeMs:)`
        /// thresholds the iPhone quiz uses, so a wrist answer and a phone
        /// answer with the same outcome/latency get the same FSRS `Grade`.
        public let responseTimeMs: Int

        public let answeredAt: Date

        public init(
            targetCharacter: String,
            answeredCharacter: String,
            isCorrect: Bool,
            responseTimeMs: Int,
            answeredAt: Date
        ) {
            self.targetCharacter = targetCharacter
            self.answeredCharacter = answeredCharacter
            self.isCorrect = isCorrect
            self.responseTimeMs = responseTimeMs
            self.answeredAt = answeredAt
        }
    }

    // MARK: - Dictionary Conversion

    /// Converts to a dictionary suitable for `WCSession.transferUserInfo`.
    public func toDictionary() -> [String: Any] {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(self),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        return dict
    }

    /// Parses from a WCSession userInfo dictionary. Returns `nil` for any
    /// dictionary that isn't this format — in particular, for a legacy
    /// `WatchSessionResult` dictionary, which lacks `kind`/`sessionId`/
    /// `events` entirely, so this always fails closed on old payloads
    /// instead of misparsing them.
    public static func fromDictionary(_ dict: [String: Any]) -> WatchQuizReviewBatch? {
        guard dict["kind"] as? String == messageKind else { return nil }
        guard let data = try? JSONSerialization.data(withJSONObject: dict) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(WatchQuizReviewBatch.self, from: data)
    }
}
