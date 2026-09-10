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

    /// Which learner profile was active on the iPhone when the Watch STARTED
    /// this nano-session — the batch's provenance stamp (GAP-17 defect 2).
    ///
    /// Everything the iPhone does with a batch resolves through the
    /// *currently* active profile (`CardRepository.activeProfileCards()`,
    /// itself keyed off `UserProfile.activeProfileIDDefaultsKey`), so without
    /// this stamp a nano-session answered under profile A and delivered after
    /// a profile switch mutates **B's** FSRS state and fabricates `ReviewLog`
    /// rows for reviews B never did. The overlap is the likely case, not the
    /// edge case: the chosen-kana-group selection
    /// (`StudySetStore.chosenGroups`) is a single global `UserDefaults` key
    /// shared by every profile, so two profiles are usually quizzed on the
    /// same characters.
    ///
    /// Optional on purpose, and it must stay optional: a Watch build that
    /// predates this field sends a dictionary without the key, and a
    /// non-optional property would fail to decode it — turning "old Watch
    /// app not yet updated" into silent data loss. `nil` therefore means
    /// "unstamped, provenance unknown", and the iPhone resolves it by
    /// counting profiles rather than guessing: exactly one live profile on
    /// the device makes mis-attribution impossible, so the batch is graded;
    /// with several profiles it cannot be attributed to any of them and is
    /// dropped (see `WatchQuizBatchAttribution`).
    ///
    /// Carried to the Watch on the same `applicationContext` dictionary as
    /// the RPG state and the eligible-kana set, under
    /// `activeProfileContextKey`.
    public let profileId: UUID?

    /// XP this nano-session claims to be worth, as computed **by the Watch**
    /// from its own tally (`WatchQuizViewModel`: one `xpPerCorrectAnswer`
    /// per correct answer).
    ///
    /// **Not authoritative, and deliberately not applied as sent.** The
    /// iPhone re-derives the amount from the answers it actually graded and
    /// treats this value only as a ceiling (`min`), because the two counts
    /// can legitimately differ: an answer can reach the phone and never be
    /// graded — no matching card, a kana group deselected between the quiz
    /// and the delivery, a card that never cleared `reps > 0`. Crediting the
    /// claim as-is awarded a full nano-session's XP for zero graded reviews
    /// and zero `ReviewLog` rows (GAP-17 defect 3); the ceiling additionally
    /// guarantees a Watch build can never be talked into inflating XP beyond
    /// what it claimed for the whole session.
    ///
    /// Still sent on the wire, and still required by `Codable`, because an
    /// **older iPhone build** paired with a newer Watch decodes this field
    /// and would reject a batch without it. XP remains an aggregate,
    /// Watch-specific bonus rather than a per-`gradeCard` award: the iPhone
    /// kana drill awards no XP for grading a card at all (XP is a
    /// main-session mechanic, see `SessionRPGPersistence`), so per-event XP
    /// here would create a *new* inconsistency instead of fixing one.
    public let xpEarned: Int

    /// XP awarded per correct answer in a Watch nano-session. Lives here,
    /// not in `WatchQuizViewModel`, so the Watch's claim and the iPhone's
    /// re-derivation are computed by the same rule instead of two constants
    /// that can drift apart.
    public static let xpPerCorrectAnswer = 5

    /// XP for `correctAnswers` correct answers, by the single shared rule.
    public static func xp(forCorrectAnswers correctAnswers: Int) -> Int {
        max(0, correctAnswers) * xpPerCorrectAnswer
    }

    /// Key the iPhone merges the active profile id (a UUID string) under, in
    /// the SAME `applicationContext` dictionary that already carries
    /// `WatchSyncPayload` and `WatchEligibleKanaPayload` — application
    /// context keeps only the latest dictionary a session sent, so a second
    /// `updateApplicationContext` call would replace the others rather than
    /// add to them (see `WatchEligibleKanaPayload`'s doc for the full
    /// reasoning).
    public static let activeProfileContextKey = "watchActiveProfileId"

    /// Reads the active profile id out of a received applicationContext.
    /// `nil` when the key is absent (an iPhone build predating GAP-17, or a
    /// context never received at all) — the Watch then sends unstamped
    /// batches, which the iPhone handles as described on `profileId`.
    public static func activeProfileId(fromContext dict: [String: Any]) -> UUID? {
        guard let raw = dict[activeProfileContextKey] as? String else { return nil }
        return UUID(uuidString: raw)
    }

    public init(sessionId: UUID = UUID(), events: [Event], xpEarned: Int, profileId: UUID? = nil) {
        self.kind = Self.messageKind
        self.sessionId = sessionId
        self.events = events
        self.xpEarned = xpEarned
        self.profileId = profileId
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
    ///
    /// `transferUserInfo` accepts property-list values only, and `NSNull`
    /// isn't one — passing one is a hard exception, not a soft failure. The
    /// synthesized `Codable` encoder already omits a nil `profileId`
    /// (optionals encode via `encodeIfPresent`), so no null should ever
    /// reach the dictionary; the filter below makes that a guarantee rather
    /// than a property of the compiler's synthesis, since the payload now
    /// carries an optional field. The wire-compatibility section of
    /// `WatchQuizBridgeTests` pins both halves.
    public func toDictionary() -> [String: Any] {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(self),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        return dict.filter { !($0.value is NSNull) }
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
