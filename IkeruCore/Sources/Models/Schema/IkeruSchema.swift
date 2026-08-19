// swiftlint:disable file_length
// This file is an append-only history of frozen `VersionedSchema` snapshots
// (V1 through V3) plus the live V4 and V5 schemas. Splitting it across files would
// break the name-shadowing trick each frozen enum relies on (nested @Model
// types must live inside their own versioned-schema enum body — see V1's doc
// comment) and would scatter a single coherent story about what shipped
// when. Growth here is expected and intentional every time a new schema
// version is cut; see IkeruSchemaTests.swift's golden-fingerprint tests for
// the actual safety net.
import Foundation
import SwiftData

// MARK: - Versioned Schema V1

/// Versioned baseline of the app's persisted SwiftData schema.
///
/// **V1 is the on-disk shape released to TestFlight before this file
/// existed** — the plain `Schema([UserProfile.self, Card.self, ...])` +
/// `ModelConfiguration("Ikeru")` container built by commit `a7371a3`, with no
/// `SchemaMigrationPlan` attached at all. Real users' stores predate
/// versioned schemas entirely; SwiftData resolves an existing store into a
/// `VersionedSchema` purely by structurally hash-matching its on-disk shape
/// against `IkeruMigrationPlan.schemas`. `IkeruSchemaV1.models` must
/// therefore byte-match `a7371a3`'s shape, or resolution fails and
/// `loadIssueModelContainer` throws — see the post-mortem below.
///
/// ### Root cause of the release-blocking migration failure (post-mortem)
///
/// `VersionedSchema.models` returns *live* type references, not snapshots.
/// Commit `aa03566` added a stored property (`RPGState.activeDaysCount`) to
/// the shared `RPGState` class **after** `IkeruSchemaV1` had already been
/// tagged as the frozen release-1 baseline — silently mutating what "V1"
/// meant, with no compiler error to catch it. From that commit onward,
/// `IkeruSchemaV1.models` actually described the *V2* shape (20-property
/// `RPGState`), not V1. Every legacy TestFlight store — created by the
/// released app with the true 19-property `RPGState` — could no longer
/// hash-match *any* schema listed in `IkeruMigrationPlan`, so `ModelContainer`
/// version resolution failed on every real in-place upgrade.
///
/// ### The fix
///
/// `RPGState` and every model that transitively reaches it through a
/// `@Relationship` — `UserProfile` (owns `rpgState`), and `Card` / `ReviewLog`
/// (reachable from `UserProfile` via `Card.profile` / `Card.reviewLogs`) — get
/// a **frozen snapshot nested inside this enum**. A nested type's simple
/// name (`RPGState`, `UserProfile`, ...) still resolves to the same
/// persisted entity name, and — because it is declared *inside*
/// `IkeruSchemaV1` — it shadows the live top-level type of the same name for
/// every unqualified reference within this enum, including in `models`
/// below. That makes it structurally impossible for a future edit to the
/// live classes to reach back and silently mutate this versioned schema
/// again: editing `RPGState.swift` no longer touches `IkeruSchemaV1.RPGState`
/// at all.
///
/// ### 2026-08-13 update — the freeze set grew to 7
///
/// Cloud-sync lot 0 (`docs/design-specs/2026-08-10-cloud-sync-design.md`
/// §5.1) adds `updatedAt` / `deletedAt` / `syncedAt` to the *live*
/// `VocabularyEntry`, `VocabularyEncounter`, and `CompanionChatMessage`
/// classes as part of `IkeruSchemaV4`. Before that change those three were
/// safe to leave live in V1/V2 — nobody had touched their shape since
/// `a7371a3`. The moment their live shape changes, the same `aa03566`
/// failure mode applies to them too: `IkeruSchemaV1.models` would silently
/// start describing V4's shape. They join the freeze set here, unchanged in
/// content from what shipped at `a7371a3` — this is a **pinning** operation
/// (adding a nested snapshot that matches the current live shape exactly),
/// not an edit to what V1 means. `VocabularyEntry` and `VocabularyEncounter`
/// are frozen together (same enum, mutual `@Relationship`) for the same
/// reason the Card/ReviewLog/UserProfile/RPGState quartet is.
///
/// Models that still cannot reach any Lot-0-touched entity through any
/// relationship (`MnemonicCache`, `AssetManifest`, `DailyTerm`) stay live
/// references: freezing them buys no additional safety while multiplying the
/// maintenance burden every future versioned schema would carry forward.
///
/// - Important: `IkeruSchemaV1.models` — and every nested frozen type below —
///   must stay byte-identical to the shape already on TestFlight users'
///   devices. **Never edit anything in this enum** to reflect a new model
///   change. Add an `IkeruSchemaV2` (or V3, ...) and a `MigrationStage`
///   between them instead. See `IkeruSchemaTests.swift`'s golden-fingerprint
///   tests, which fail loudly if a referenced `@Model`'s stored shape drifts
///   out from under a frozen versioned schema.
public enum IkeruSchemaV1: VersionedSchema {

    public static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }

    public static var models: [any PersistentModel.Type] {
        // The first four bind to the frozen nested snapshots below via name
        // shadowing. ⚠️ Do NOT "clarify" them to `IkeruSchemaV1.UserProfile.self`
        // etc.: self-qualifying the nested @Model types from inside this enum's
        // own body empirically breaks SwiftData's class↔entity resolution at
        // runtime ("Failed to cast model IkeruCore.UserProfile … to UserProfile"
        // in the migration tests) — bisected 2026-07-15. The golden fingerprint
        // tests in IkeruSchemaTests pin that these resolve to the frozen
        // 19-property shapes; if this list is ever moved out of the enum
        // body, those tests fail before anything ships. Same rule applies to
        // `VocabularyEntry` / `VocabularyEncounter` / `CompanionChatMessage`,
        // frozen here since 2026-08-13 (cloud-sync lot 0).
        [
            UserProfile.self,
            Card.self,
            ReviewLog.self,
            RPGState.self,
            MnemonicCache.self,
            CompanionChatMessage.self,
            AssetManifest.self,
            VocabularyEntry.self,
            VocabularyEncounter.self,
            DailyTerm.self,
        ]
    }

    // MARK: - Frozen snapshots

    /// Frozen snapshot of `RPGState` exactly as it stood at `a7371a3` — the
    /// 19-stored-property shape that is actually on every TestFlight user's
    /// disk today. **Never add, remove, retype, or rename a stored property
    /// here.** The live `RPGState.swift` has since grown `activeDaysCount`
    /// (commit `aa03566`); that property belongs only in `IkeruSchemaV2`.
    @Model
    public final class RPGState {

        /// Unique identifier for the RPG state
        public var id: UUID

        /// Total experience points earned
        public var xp: Int

        /// Current level
        public var level: Int

        /// Total number of reviews completed across all sessions
        public var totalReviewsCompleted: Int

        /// JSON-encoded RPGAttribute array.
        public var attributesData: Data?

        /// JSON-encoded LootItem array.
        public var lootInventoryData: Data?

        /// JSON-encoded LootBox array.
        public var lootBoxesData: Data?

        /// Total sessions completed (used for lootbox milestone detection).
        public var totalSessionsCompleted: Int

        /// Currently equipped title item id (category == .title). Nil if none.
        public var equippedTitleID: UUID?

        /// Currently equipped theme item id (category == .theme). Nil if none.
        public var equippedThemeID: UUID?

        /// JSON-encoded [UUID] of equipped badge ids (max 3).
        public var equippedBadgeIDsData: Data?

        /// JSON-encoded `Set<ExerciseType>` of acknowledged unlock badges.
        public var acknowledgedUnlocksData: Data?

        /// Count of consecutive sessions that ended with zero drops.
        public var sessionsSinceLastDrop: Int = 0

        /// Date of the most recent completed session.
        public var lastSessionDate: Date?

        /// Current consecutive daily-session streak.
        public var currentDailyStreak: Int = 0

        /// Highest daily streak reached, for posterity.
        public var longestDailyStreak: Int = 0

        /// One-shot JLPT backfill schema version.
        public var jlptBackfillVersion: Int = 0

        /// Last `JLPTReadinessReport.bestFit` raw value observed.
        public var lastReadinessBestFit: String?

        /// The user profile that owns this RPG state
        public var profile: UserProfile?

        public init(
            xp: Int = 0,
            level: Int = 1,
            totalReviewsCompleted: Int = 0
        ) {
            self.id = UUID()
            self.xp = xp
            self.level = level
            self.totalReviewsCompleted = totalReviewsCompleted
            self.attributesData = nil
            self.lootInventoryData = nil
            self.lootBoxesData = nil
            self.totalSessionsCompleted = 0
            self.equippedTitleID = nil
            self.equippedThemeID = nil
            self.equippedBadgeIDsData = nil
            self.sessionsSinceLastDrop = 0
            self.lastSessionDate = nil
            self.currentDailyStreak = 0
            self.longestDailyStreak = 0
        }
    }

    /// Frozen snapshot of `UserProfile`. Unchanged from `a7371a3` through
    /// HEAD — nested here only so its `rpgState` relationship's inverse can
    /// point at the frozen `RPGState` above instead of the live (drifted)
    /// class; SwiftData relationships must resolve within a single
    /// `VersionedSchema`.
    @Model
    public final class UserProfile: Identifiable {

        /// Unique identifier for the profile
        public var id: UUID

        /// Display name for the user
        public var displayName: String

        /// When the profile was created
        public var createdAt: Date

        /// User-configurable learning settings
        public var settings: ProfileSettings

        /// All cards belonging to this profile
        @Relationship(deleteRule: .cascade, inverse: \Card.profile)
        public var cards: [Card]?

        /// RPG progression state for this profile
        @Relationship(deleteRule: .cascade, inverse: \RPGState.profile)
        public var rpgState: RPGState?

        public init(
            displayName: String,
            settings: ProfileSettings = ProfileSettings()
        ) {
            self.id = UUID()
            self.displayName = displayName
            self.createdAt = Date()
            self.settings = settings
            self.cards = []
            self.rpgState = RPGState()
        }
    }

    /// Frozen snapshot of `Card`. Unchanged from `a7371a3` through HEAD —
    /// nested here only so its `profile` property can point at the frozen
    /// `UserProfile` above.
    @Model
    public final class Card {

        /// Unique identifier for the card
        public var id: UUID

        /// The front face content (question/prompt)
        public var front: String

        /// The back face content (answer)
        public var back: String

        /// Raw value storage for CardType (used in SwiftData predicates).
        public var typeRawValue: String

        /// The type of learning material this card represents.
        public var type: CardType {
            get { CardType(rawValue: typeRawValue) ?? .kanji }
            set { typeRawValue = newValue.rawValue }
        }

        /// FSRS scheduling state stored as a Codable struct
        public var fsrsState: FSRSState

        /// Ease factor for scheduling (default 2.5)
        public var easeFactor: Double

        /// Current review interval in days
        public var interval: Int

        /// Date when the card is next due for review
        public var dueDate: Date

        /// Number of times the card has lapsed (been forgotten)
        public var lapseCount: Int

        /// Whether this card is flagged as a leech (frequently forgotten)
        public var leechFlag: Bool

        /// Raw value storage for the optional JLPT level.
        public var jlptLevelRawValue: String?

        /// Optional JLPT level tag — `.n5` through `.n1`, or `nil`.
        public var jlptLevel: JLPTLevel? {
            get {
                guard let raw = jlptLevelRawValue else { return nil }
                return JLPTLevel(rawValue: raw)
            }
            set { jlptLevelRawValue = newValue?.rawValue }
        }

        /// The user profile that owns this card
        public var profile: UserProfile?

        /// All review logs for this card
        @Relationship(deleteRule: .cascade, inverse: \ReviewLog.card)
        public var reviewLogs: [ReviewLog]?

        public init(
            front: String,
            back: String,
            type: CardType,
            fsrsState: FSRSState = FSRSState(),
            easeFactor: Double = 2.5,
            interval: Int = 0,
            dueDate: Date = Date(),
            lapseCount: Int = 0,
            leechFlag: Bool = false,
            jlptLevel: JLPTLevel? = nil
        ) {
            self.id = UUID()
            self.front = front
            self.back = back
            self.typeRawValue = type.rawValue
            self.fsrsState = fsrsState
            self.easeFactor = easeFactor
            self.interval = interval
            self.dueDate = dueDate
            self.lapseCount = lapseCount
            self.leechFlag = leechFlag
            self.jlptLevelRawValue = jlptLevel?.rawValue
            self.reviewLogs = []
        }
    }

    /// Frozen snapshot of `ReviewLog`. Unchanged from `a7371a3` through
    /// HEAD — nested here only so its `card` property can point at the
    /// frozen `Card` above.
    @Model
    public final class ReviewLog {

        /// Unique identifier for this review log entry
        public var id: UUID

        /// Timestamp when the review occurred
        public var timestamp: Date

        /// The card that was reviewed
        public var card: Card?

        /// Raw value storage for Grade (used in SwiftData predicates).
        public var gradeRawValue: Int

        /// The grade given during this review
        public var grade: Grade {
            get { Grade(rawValue: gradeRawValue) ?? .good }
            set { gradeRawValue = newValue.rawValue }
        }

        /// Response time in milliseconds
        public var responseTimeMs: Int

        public init(
            card: Card,
            grade: Grade,
            responseTimeMs: Int,
            timestamp: Date = Date()
        ) {
            self.id = UUID()
            self.timestamp = timestamp
            self.card = card
            self.gradeRawValue = grade.rawValue
            self.responseTimeMs = responseTimeMs
        }
    }

    /// Frozen snapshot of `VocabularyEntry`, unchanged since `a7371a3`.
    /// Frozen here since 2026-08-13 (cloud-sync lot 0) — the live class
    /// gains `updatedAt`/`deletedAt`/`syncedAt` in `IkeruSchemaV4`. Nested
    /// together with `VocabularyEncounter` below because the two hold a
    /// mutual `@Relationship`.
    @Model
    public final class VocabularyEntry {

        /// Unique identifier for the entry.
        public var id: UUID

        /// The Japanese word (e.g. 勉強).
        public var word: String

        /// Hiragana reading (e.g. べんきょう).
        public var reading: String

        /// Translation in the user's language.
        public var meaning: String

        /// Raw value storage for JLPTLevel (used in SwiftData predicates).
        public var jlptLevelRawValue: String?

        /// Estimated JLPT level for this word.
        public var jlptLevel: JLPTLevel? {
            get {
                guard let raw = jlptLevelRawValue else { return nil }
                return JLPTLevel(rawValue: raw)
            }
            set { jlptLevelRawValue = newValue?.rawValue }
        }

        /// FSRS scheduling state.
        public var fsrsState: FSRSState

        /// Ease factor for scheduling (default 2.5).
        public var easeFactor: Double

        /// Current review interval in days.
        public var interval: Int

        /// Date when the entry is next due for review.
        public var dueDate: Date

        /// Number of times the entry has lapsed (been forgotten).
        public var lapseCount: Int

        /// Whether the user explicitly added this word to their dictionary.
        public var isInDictionary: Bool = false

        /// Date when the entry was first added to the dictionary.
        public var createdAt: Date

        /// All encounter logs for this entry.
        @Relationship(deleteRule: .cascade, inverse: \VocabularyEncounter.entry)
        public var encounters: [VocabularyEncounter]?

        public init(
            word: String,
            reading: String,
            meaning: String,
            jlptLevel: JLPTLevel? = nil,
            isInDictionary: Bool = true,
            fsrsState: FSRSState = FSRSState(),
            easeFactor: Double = 2.5,
            interval: Int = 0,
            dueDate: Date = Date(),
            lapseCount: Int = 0,
            createdAt: Date = Date()
        ) {
            self.id = UUID()
            self.word = word
            self.reading = reading
            self.meaning = meaning
            self.jlptLevelRawValue = jlptLevel?.rawValue
            self.isInDictionary = isInDictionary
            self.fsrsState = fsrsState
            self.easeFactor = easeFactor
            self.interval = interval
            self.dueDate = dueDate
            self.lapseCount = lapseCount
            self.createdAt = createdAt
            self.encounters = []
        }
    }

    /// Frozen snapshot of `VocabularyEncounter`, unchanged since `a7371a3`.
    /// Frozen here since 2026-08-13 (cloud-sync lot 0) — see
    /// `VocabularyEntry` above for why the pair is nested together.
    @Model
    public final class VocabularyEncounter {

        /// Unique identifier for this encounter.
        public var id: UUID

        /// Timestamp of the encounter.
        public var timestamp: Date

        /// Raw value storage for EncounterSource (used in SwiftData predicates).
        public var sourceRawValue: String

        /// Where in the app the word was encountered.
        public var source: EncounterSource {
            get { EncounterSource(rawValue: sourceRawValue) ?? .sakuraChat }
            set { sourceRawValue = newValue.rawValue }
        }

        /// The sentence or context where the word appeared.
        public var contextSnippet: String

        /// The vocabulary entry this encounter belongs to.
        public var entry: VocabularyEntry?

        public init(
            source: EncounterSource,
            contextSnippet: String,
            entry: VocabularyEntry,
            timestamp: Date = Date()
        ) {
            self.id = UUID()
            self.timestamp = timestamp
            self.sourceRawValue = source.rawValue
            self.contextSnippet = contextSnippet
            self.entry = entry
        }
    }

    /// Frozen snapshot of `CompanionChatMessage`, unchanged since `a7371a3`.
    /// Frozen here since 2026-08-13 (cloud-sync lot 0) — the live class
    /// gains `updatedAt`/`deletedAt`/`syncedAt` in `IkeruSchemaV4`.
    @Model
    public final class CompanionChatMessage {

        /// Unique identifier for the message.
        public var id: UUID

        /// Who sent the message.
        public var roleRawValue: String

        /// The raw content of the message (may contain inline tags).
        public var content: String

        /// When the message was created.
        public var createdAt: Date

        /// The profile this message belongs to.
        public var profileId: UUID

        /// Typed role accessor.
        @Transient
        public var role: CompanionMessageRole {
            CompanionMessageRole(rawValue: roleRawValue) ?? .system
        }

        public init(
            role: CompanionMessageRole,
            content: String,
            profileId: UUID
        ) {
            self.id = UUID()
            self.roleRawValue = role.rawValue
            self.content = content
            self.createdAt = Date()
            self.profileId = profileId
        }
    }
}

// MARK: - Versioned Schema V2

/// **V2** — frozen now that `IkeruSchemaV3` exists (learner-telemetry lot 1,
/// remediation item #17). Two additive changes on top of V1:
///
/// 1. `RPGState.activeDaysCount` (commit `aa03566`) — a new stored `Int`
///    property, defaulting to `0`. This is the property whose addition to
///    the *live* `RPGState` class silently mutated `IkeruSchemaV1`'s meaning
///    before V1 was frozen (see the post-mortem in `IkeruSchemaV1`'s doc
///    comment); it only ever existed from V2 onward.
/// 2. `ExerciseOutcomeLog` (remediation 4.4) — a brand-new entity whose only
///    cross-entity reference is a scalar `profileID: UUID` (not a SwiftData
///    relationship), so it doesn't change any existing entity's shape.
///
/// Both changes were lightweight-safe: an added scalar property with a
/// default, and a wholly new entity.
///
/// ### 2026-08-13 update — the freeze set grew to 8
///
/// Same reasoning as `IkeruSchemaV1`'s 2026-08-13 update: cloud-sync lot 0
/// touches the live `VocabularyEntry`, `VocabularyEncounter`,
/// `CompanionChatMessage`, **and** `ExerciseOutcomeLog` (all four gain
/// `updatedAt`/`deletedAt`/`syncedAt` in `IkeruSchemaV4`), so all four join
/// the freeze set here too — unchanged in content from what V2 actually
/// shipped, this is a pinning operation, not an edit.
///
/// - Important: `IkeruSchemaV2.models` — and every nested frozen type below —
///   must stay byte-identical to what shipped as "V2" (the shape released to
///   TestFlight before `ReviewLog` gained `answeredValue`/`exerciseType`/
///   `surface`). **Never edit anything in this enum** to reflect a new model
///   change; that goes in `IkeruSchemaV3` (or later) plus a `MigrationStage`.
///   See the golden-fingerprint tests in `IkeruSchemaTests.swift`.
///
/// ⚠️ Freezing V2 means every OTHER call site that opens a container with
/// `Schema(versionedSchema: IkeruSchemaV2.self)` (or `Schema(IkeruSchemaV2.models)`)
/// and then fetches/inserts using the *live* top-level types (`UserProfile`,
/// `Card`, `ReviewLog`, `RPGState`) will now hit the same
/// "Failed to cast model … to X" mismatch V1's post-mortem describes, because
/// those live types now describe V3's shape, not V2's. As of this change the
/// only call sites still opening V2 directly are OUTSIDE this remediation
/// item's file perimeter (production bootstrap + several test files) — see
/// the handoff notes for the exact list. They must be repointed at
/// `IkeruSchemaV3` before V2's freeze is safe to ship.
public enum IkeruSchemaV2: VersionedSchema {

    public static var versionIdentifier: Schema.Version { Schema.Version(2, 0, 0) }

    public static var models: [any PersistentModel.Type] {
        // The first four bind to the frozen nested snapshots below via name
        // shadowing. ⚠️ Do NOT "clarify" them to `IkeruSchemaV2.UserProfile.self`
        // etc.: self-qualifying the nested @Model types from inside this enum's
        // own body empirically breaks SwiftData's class↔entity resolution at
        // runtime ("Failed to cast model IkeruCore.UserProfile … to UserProfile"
        // in the migration tests) — bisected 2026-07-15 (same pitfall as V1).
        // The golden fingerprint tests in IkeruSchemaTests pin that these
        // resolve to the frozen 20-property (RPGState) / 5-property
        // (ReviewLog) shapes; if this list is ever moved out of the enum
        // body, those tests fail before anything ships. Same rule applies to
        // `VocabularyEntry` / `VocabularyEncounter` / `CompanionChatMessage` /
        // `ExerciseOutcomeLog`, frozen here since 2026-08-13 (cloud-sync lot 0).
        [
            UserProfile.self,
            Card.self,
            ReviewLog.self,
            RPGState.self,
            MnemonicCache.self,
            CompanionChatMessage.self,
            AssetManifest.self,
            VocabularyEntry.self,
            VocabularyEncounter.self,
            DailyTerm.self,
            ExerciseOutcomeLog.self,
        ]
    }

    // MARK: - Frozen snapshots

    /// Frozen snapshot of `RPGState` as it stood for V2 — the 20-stored-
    /// property shape (V1's 19 plus `activeDaysCount`). **Never add, remove,
    /// retype, or rename a stored property here.**
    @Model
    public final class RPGState {

        public var id: UUID
        public var xp: Int
        public var level: Int
        public var totalReviewsCompleted: Int
        public var attributesData: Data?
        public var lootInventoryData: Data?
        public var lootBoxesData: Data?
        public var totalSessionsCompleted: Int
        public var equippedTitleID: UUID?
        public var equippedThemeID: UUID?
        public var equippedBadgeIDsData: Data?
        public var acknowledgedUnlocksData: Data?
        public var sessionsSinceLastDrop: Int = 0
        public var lastSessionDate: Date?
        public var currentDailyStreak: Int = 0
        public var longestDailyStreak: Int = 0

        /// Added in V2 (commit `aa03566`) — see this enum's doc comment.
        public var activeDaysCount: Int = 0

        public var jlptBackfillVersion: Int = 0
        public var lastReadinessBestFit: String?
        public var profile: UserProfile?

        public init(
            xp: Int = 0,
            level: Int = 1,
            totalReviewsCompleted: Int = 0
        ) {
            self.id = UUID()
            self.xp = xp
            self.level = level
            self.totalReviewsCompleted = totalReviewsCompleted
            self.attributesData = nil
            self.lootInventoryData = nil
            self.lootBoxesData = nil
            self.totalSessionsCompleted = 0
            self.equippedTitleID = nil
            self.equippedThemeID = nil
            self.equippedBadgeIDsData = nil
            self.sessionsSinceLastDrop = 0
            self.lastSessionDate = nil
            self.currentDailyStreak = 0
            self.longestDailyStreak = 0
        }
    }

    /// Frozen snapshot of `UserProfile` for V2 — unchanged from V1.
    @Model
    public final class UserProfile: Identifiable {

        public var id: UUID
        public var displayName: String
        public var createdAt: Date
        public var settings: ProfileSettings

        @Relationship(deleteRule: .cascade, inverse: \Card.profile)
        public var cards: [Card]?

        @Relationship(deleteRule: .cascade, inverse: \RPGState.profile)
        public var rpgState: RPGState?

        public init(
            displayName: String,
            settings: ProfileSettings = ProfileSettings()
        ) {
            self.id = UUID()
            self.displayName = displayName
            self.createdAt = Date()
            self.settings = settings
            self.cards = []
            self.rpgState = RPGState()
        }
    }

    /// Frozen snapshot of `Card` for V2 — unchanged from V1.
    @Model
    public final class Card {

        public var id: UUID
        public var front: String
        public var back: String
        public var typeRawValue: String

        public var type: CardType {
            get { CardType(rawValue: typeRawValue) ?? .kanji }
            set { typeRawValue = newValue.rawValue }
        }

        public var fsrsState: FSRSState
        public var easeFactor: Double
        public var interval: Int
        public var dueDate: Date
        public var lapseCount: Int
        public var leechFlag: Bool
        public var jlptLevelRawValue: String?

        public var jlptLevel: JLPTLevel? {
            get {
                guard let raw = jlptLevelRawValue else { return nil }
                return JLPTLevel(rawValue: raw)
            }
            set { jlptLevelRawValue = newValue?.rawValue }
        }

        public var profile: UserProfile?

        @Relationship(deleteRule: .cascade, inverse: \ReviewLog.card)
        public var reviewLogs: [ReviewLog]?

        public init(
            front: String,
            back: String,
            type: CardType,
            fsrsState: FSRSState = FSRSState(),
            easeFactor: Double = 2.5,
            interval: Int = 0,
            dueDate: Date = Date(),
            lapseCount: Int = 0,
            leechFlag: Bool = false,
            jlptLevel: JLPTLevel? = nil
        ) {
            self.id = UUID()
            self.front = front
            self.back = back
            self.typeRawValue = type.rawValue
            self.fsrsState = fsrsState
            self.easeFactor = easeFactor
            self.interval = interval
            self.dueDate = dueDate
            self.lapseCount = lapseCount
            self.leechFlag = leechFlag
            self.jlptLevelRawValue = jlptLevel?.rawValue
            self.reviewLogs = []
        }
    }

    /// Frozen snapshot of `ReviewLog` for V2 — the 5-stored-property shape
    /// **without** `answeredValue`/`exerciseType`/`surface`. Those are
    /// V3-only; see `IkeruSchemaV3`.
    @Model
    public final class ReviewLog {

        public var id: UUID
        public var timestamp: Date
        public var card: Card?
        public var gradeRawValue: Int

        public var grade: Grade {
            get { Grade(rawValue: gradeRawValue) ?? .good }
            set { gradeRawValue = newValue.rawValue }
        }

        public var responseTimeMs: Int

        public init(
            card: Card,
            grade: Grade,
            responseTimeMs: Int,
            timestamp: Date = Date()
        ) {
            self.id = UUID()
            self.timestamp = timestamp
            self.card = card
            self.gradeRawValue = grade.rawValue
            self.responseTimeMs = responseTimeMs
        }
    }

    /// Frozen snapshot of `VocabularyEntry` for V2 — unchanged from V1.
    /// Frozen here since 2026-08-13 (cloud-sync lot 0) — see
    /// `IkeruSchemaV1.VocabularyEntry`'s doc comment.
    @Model
    public final class VocabularyEntry {

        public var id: UUID
        public var word: String
        public var reading: String
        public var meaning: String
        public var jlptLevelRawValue: String?

        public var jlptLevel: JLPTLevel? {
            get {
                guard let raw = jlptLevelRawValue else { return nil }
                return JLPTLevel(rawValue: raw)
            }
            set { jlptLevelRawValue = newValue?.rawValue }
        }

        public var fsrsState: FSRSState
        public var easeFactor: Double
        public var interval: Int
        public var dueDate: Date
        public var lapseCount: Int
        public var isInDictionary: Bool = false
        public var createdAt: Date

        @Relationship(deleteRule: .cascade, inverse: \VocabularyEncounter.entry)
        public var encounters: [VocabularyEncounter]?

        public init(
            word: String,
            reading: String,
            meaning: String,
            jlptLevel: JLPTLevel? = nil,
            isInDictionary: Bool = true,
            fsrsState: FSRSState = FSRSState(),
            easeFactor: Double = 2.5,
            interval: Int = 0,
            dueDate: Date = Date(),
            lapseCount: Int = 0,
            createdAt: Date = Date()
        ) {
            self.id = UUID()
            self.word = word
            self.reading = reading
            self.meaning = meaning
            self.jlptLevelRawValue = jlptLevel?.rawValue
            self.isInDictionary = isInDictionary
            self.fsrsState = fsrsState
            self.easeFactor = easeFactor
            self.interval = interval
            self.dueDate = dueDate
            self.lapseCount = lapseCount
            self.createdAt = createdAt
            self.encounters = []
        }
    }

    /// Frozen snapshot of `VocabularyEncounter` for V2 — unchanged from V1.
    @Model
    public final class VocabularyEncounter {

        public var id: UUID
        public var timestamp: Date
        public var sourceRawValue: String

        public var source: EncounterSource {
            get { EncounterSource(rawValue: sourceRawValue) ?? .sakuraChat }
            set { sourceRawValue = newValue.rawValue }
        }

        public var contextSnippet: String
        public var entry: VocabularyEntry?

        public init(
            source: EncounterSource,
            contextSnippet: String,
            entry: VocabularyEntry,
            timestamp: Date = Date()
        ) {
            self.id = UUID()
            self.timestamp = timestamp
            self.sourceRawValue = source.rawValue
            self.contextSnippet = contextSnippet
            self.entry = entry
        }
    }

    /// Frozen snapshot of `CompanionChatMessage` for V2 — unchanged from V1.
    @Model
    public final class CompanionChatMessage {

        public var id: UUID
        public var roleRawValue: String
        public var content: String
        public var createdAt: Date
        public var profileId: UUID

        @Transient
        public var role: CompanionMessageRole {
            CompanionMessageRole(rawValue: roleRawValue) ?? .system
        }

        public init(
            role: CompanionMessageRole,
            content: String,
            profileId: UUID
        ) {
            self.id = UUID()
            self.roleRawValue = role.rawValue
            self.content = content
            self.createdAt = Date()
            self.profileId = profileId
        }
    }

    /// Frozen snapshot of `ExerciseOutcomeLog` for V2 — the shape it had at
    /// introduction. Frozen here since 2026-08-13 (cloud-sync lot 0) — the
    /// live class gains `updatedAt`/`deletedAt`/`syncedAt` in `IkeruSchemaV4`.
    @Model
    public final class ExerciseOutcomeLog {

        public var id: UUID
        public var timestamp: Date
        public var skillRawValue: String
        public var accuracy: Double
        public var profileID: UUID

        public var skill: SkillType {
            get { SkillType(rawValue: skillRawValue) ?? .listening }
            set { skillRawValue = newValue.rawValue }
        }

        public init(
            skill: SkillType,
            accuracy: Double,
            profileID: UUID,
            timestamp: Date = Date()
        ) {
            self.id = UUID()
            self.timestamp = timestamp
            self.skillRawValue = skill.rawValue
            self.accuracy = accuracy
            self.profileID = profileID
        }
    }
}

// MARK: - Versioned Schema V3

/// **V3** — frozen now that `IkeruSchemaV4` exists (cloud-sync lot 0,
/// `docs/design-specs/2026-08-10-cloud-sync-design.md` §5.1). One additive
/// change on top of V2:
///
/// `ReviewLog` gains three optional stored properties —  `answeredValue`,
/// `exerciseType`, `surface` — so a review log entry can carry which value
/// the learner actually chose (for confusion-pair analysis) and where the
/// grade came from. All three default to `nil`, so this is lightweight-safe:
/// existing V2 rows backfill as `nil` with no data transformation needed.
///
/// ### 2026-08-13 update — V3 is now frozen, with a full 8-entity freeze set
///
/// V3 used to describe itself as "the fully live current shape" because
/// there was no V4 yet. `IkeruSchemaV4` now exists: it adds `updatedAt` /
/// `deletedAt` / `syncedAt` to the 8 synchronized entities per the cloud-sync
/// design (`UserProfile`, `Card`, `ReviewLog`, `RPGState`, `VocabularyEntry`,
/// `VocabularyEncounter`, `ExerciseOutcomeLog`, `CompanionChatMessage`). All
/// 8 are therefore frozen here, nested exactly as they stood before that
/// addition — this is what makes V3→V4 a legitimate `.lightweight` stage
/// instead of silently mutating what "V3" already meant.
///
/// `MnemonicCache`, `AssetManifest`, `DailyTerm` are unaffected by lot 0 (not
/// synchronized entities — see spec §3) and stay live references.
///
/// - Important: `IkeruSchemaV3.models` — and every nested frozen type below —
///   must stay byte-identical to what shipped as "V3". **Never edit anything
///   in this enum** to reflect a new model change; that goes in
///   `IkeruSchemaV4` (or later) plus a `MigrationStage`. See the
///   golden-fingerprint tests in `IkeruSchemaTests.swift`.
public enum IkeruSchemaV3: VersionedSchema {

    public static var versionIdentifier: Schema.Version { Schema.Version(3, 0, 0) }

    public static var models: [any PersistentModel.Type] {
        // Name-shadowing rule applies here exactly as in V1/V2 — see their
        // comments on `models`. Do NOT self-qualify these to
        // `IkeruSchemaV3.UserProfile.self` etc.
        [
            UserProfile.self,
            Card.self,
            ReviewLog.self,
            RPGState.self,
            MnemonicCache.self,
            CompanionChatMessage.self,
            AssetManifest.self,
            VocabularyEntry.self,
            VocabularyEncounter.self,
            DailyTerm.self,
            ExerciseOutcomeLog.self,
        ]
    }

    // MARK: - Frozen snapshots

    /// Frozen snapshot of `RPGState` for V3 — identical to V2's (RPGState
    /// gained nothing between V2 and V3).
    @Model
    public final class RPGState {

        public var id: UUID
        public var xp: Int
        public var level: Int
        public var totalReviewsCompleted: Int
        public var attributesData: Data?
        public var lootInventoryData: Data?
        public var lootBoxesData: Data?
        public var totalSessionsCompleted: Int
        public var equippedTitleID: UUID?
        public var equippedThemeID: UUID?
        public var equippedBadgeIDsData: Data?
        public var acknowledgedUnlocksData: Data?
        public var sessionsSinceLastDrop: Int = 0
        public var lastSessionDate: Date?
        public var currentDailyStreak: Int = 0
        public var longestDailyStreak: Int = 0
        public var activeDaysCount: Int = 0
        public var jlptBackfillVersion: Int = 0
        public var lastReadinessBestFit: String?
        public var profile: UserProfile?

        public init(
            xp: Int = 0,
            level: Int = 1,
            totalReviewsCompleted: Int = 0
        ) {
            self.id = UUID()
            self.xp = xp
            self.level = level
            self.totalReviewsCompleted = totalReviewsCompleted
            self.attributesData = nil
            self.lootInventoryData = nil
            self.lootBoxesData = nil
            self.totalSessionsCompleted = 0
            self.equippedTitleID = nil
            self.equippedThemeID = nil
            self.equippedBadgeIDsData = nil
            self.sessionsSinceLastDrop = 0
            self.lastSessionDate = nil
            self.currentDailyStreak = 0
            self.longestDailyStreak = 0
        }
    }

    /// Frozen snapshot of `UserProfile` for V3 — unchanged from V1/V2.
    @Model
    public final class UserProfile: Identifiable {

        public var id: UUID
        public var displayName: String
        public var createdAt: Date
        public var settings: ProfileSettings

        @Relationship(deleteRule: .cascade, inverse: \Card.profile)
        public var cards: [Card]?

        @Relationship(deleteRule: .cascade, inverse: \RPGState.profile)
        public var rpgState: RPGState?

        public init(
            displayName: String,
            settings: ProfileSettings = ProfileSettings()
        ) {
            self.id = UUID()
            self.displayName = displayName
            self.createdAt = Date()
            self.settings = settings
            self.cards = []
            self.rpgState = RPGState()
        }
    }

    /// Frozen snapshot of `Card` for V3 — unchanged from V1/V2.
    @Model
    public final class Card {

        public var id: UUID
        public var front: String
        public var back: String
        public var typeRawValue: String

        public var type: CardType {
            get { CardType(rawValue: typeRawValue) ?? .kanji }
            set { typeRawValue = newValue.rawValue }
        }

        public var fsrsState: FSRSState
        public var easeFactor: Double
        public var interval: Int
        public var dueDate: Date
        public var lapseCount: Int
        public var leechFlag: Bool
        public var jlptLevelRawValue: String?

        public var jlptLevel: JLPTLevel? {
            get {
                guard let raw = jlptLevelRawValue else { return nil }
                return JLPTLevel(rawValue: raw)
            }
            set { jlptLevelRawValue = newValue?.rawValue }
        }

        public var profile: UserProfile?

        @Relationship(deleteRule: .cascade, inverse: \ReviewLog.card)
        public var reviewLogs: [ReviewLog]?

        public init(
            front: String,
            back: String,
            type: CardType,
            fsrsState: FSRSState = FSRSState(),
            easeFactor: Double = 2.5,
            interval: Int = 0,
            dueDate: Date = Date(),
            lapseCount: Int = 0,
            leechFlag: Bool = false,
            jlptLevel: JLPTLevel? = nil
        ) {
            self.id = UUID()
            self.front = front
            self.back = back
            self.typeRawValue = type.rawValue
            self.fsrsState = fsrsState
            self.easeFactor = easeFactor
            self.interval = interval
            self.dueDate = dueDate
            self.lapseCount = lapseCount
            self.leechFlag = leechFlag
            self.jlptLevelRawValue = jlptLevel?.rawValue
            self.reviewLogs = []
        }
    }

    /// Frozen snapshot of `ReviewLog` for V3 — the 8-stored-property shape
    /// **with** `answeredValue`/`exerciseType`/`surface`, but without the
    /// cloud-sync columns (V4-only).
    @Model
    public final class ReviewLog {

        public var id: UUID
        public var timestamp: Date
        public var card: Card?
        public var gradeRawValue: Int

        public var grade: Grade {
            get { Grade(rawValue: gradeRawValue) ?? .good }
            set { gradeRawValue = newValue.rawValue }
        }

        public var responseTimeMs: Int
        public var answeredValue: String?
        public var exerciseType: String?
        public var surface: String?

        public init(
            card: Card,
            grade: Grade,
            responseTimeMs: Int,
            timestamp: Date = Date(),
            answeredValue: String? = nil,
            exerciseType: String? = nil,
            surface: String? = nil
        ) {
            self.id = UUID()
            self.timestamp = timestamp
            self.card = card
            self.gradeRawValue = grade.rawValue
            self.responseTimeMs = responseTimeMs
            self.answeredValue = answeredValue
            self.exerciseType = exerciseType
            self.surface = surface
        }
    }

    /// Frozen snapshot of `VocabularyEntry` for V3 — unchanged from V1/V2.
    @Model
    public final class VocabularyEntry {

        public var id: UUID
        public var word: String
        public var reading: String
        public var meaning: String
        public var jlptLevelRawValue: String?

        public var jlptLevel: JLPTLevel? {
            get {
                guard let raw = jlptLevelRawValue else { return nil }
                return JLPTLevel(rawValue: raw)
            }
            set { jlptLevelRawValue = newValue?.rawValue }
        }

        public var fsrsState: FSRSState
        public var easeFactor: Double
        public var interval: Int
        public var dueDate: Date
        public var lapseCount: Int
        public var isInDictionary: Bool = false
        public var createdAt: Date

        @Relationship(deleteRule: .cascade, inverse: \VocabularyEncounter.entry)
        public var encounters: [VocabularyEncounter]?

        public init(
            word: String,
            reading: String,
            meaning: String,
            jlptLevel: JLPTLevel? = nil,
            isInDictionary: Bool = true,
            fsrsState: FSRSState = FSRSState(),
            easeFactor: Double = 2.5,
            interval: Int = 0,
            dueDate: Date = Date(),
            lapseCount: Int = 0,
            createdAt: Date = Date()
        ) {
            self.id = UUID()
            self.word = word
            self.reading = reading
            self.meaning = meaning
            self.jlptLevelRawValue = jlptLevel?.rawValue
            self.isInDictionary = isInDictionary
            self.fsrsState = fsrsState
            self.easeFactor = easeFactor
            self.interval = interval
            self.dueDate = dueDate
            self.lapseCount = lapseCount
            self.createdAt = createdAt
            self.encounters = []
        }
    }

    /// Frozen snapshot of `VocabularyEncounter` for V3 — unchanged from V1/V2.
    @Model
    public final class VocabularyEncounter {

        public var id: UUID
        public var timestamp: Date
        public var sourceRawValue: String

        public var source: EncounterSource {
            get { EncounterSource(rawValue: sourceRawValue) ?? .sakuraChat }
            set { sourceRawValue = newValue.rawValue }
        }

        public var contextSnippet: String
        public var entry: VocabularyEntry?

        public init(
            source: EncounterSource,
            contextSnippet: String,
            entry: VocabularyEntry,
            timestamp: Date = Date()
        ) {
            self.id = UUID()
            self.timestamp = timestamp
            self.sourceRawValue = source.rawValue
            self.contextSnippet = contextSnippet
            self.entry = entry
        }
    }

    /// Frozen snapshot of `CompanionChatMessage` for V3 — unchanged from V1/V2.
    @Model
    public final class CompanionChatMessage {

        public var id: UUID
        public var roleRawValue: String
        public var content: String
        public var createdAt: Date
        public var profileId: UUID

        @Transient
        public var role: CompanionMessageRole {
            CompanionMessageRole(rawValue: roleRawValue) ?? .system
        }

        public init(
            role: CompanionMessageRole,
            content: String,
            profileId: UUID
        ) {
            self.id = UUID()
            self.roleRawValue = role.rawValue
            self.content = content
            self.createdAt = Date()
            self.profileId = profileId
        }
    }

    /// Frozen snapshot of `ExerciseOutcomeLog` for V3 — unchanged from V2.
    @Model
    public final class ExerciseOutcomeLog {

        public var id: UUID
        public var timestamp: Date
        public var skillRawValue: String
        public var accuracy: Double
        public var profileID: UUID

        public var skill: SkillType {
            get { SkillType(rawValue: skillRawValue) ?? .listening }
            set { skillRawValue = newValue.rawValue }
        }

        public init(
            skill: SkillType,
            accuracy: Double,
            profileID: UUID,
            timestamp: Date = Date()
        ) {
            self.id = UUID()
            self.timestamp = timestamp
            self.skillRawValue = skill.rawValue
            self.accuracy = accuracy
            self.profileID = profileID
        }
    }
}

// MARK: - Versioned Schema V4

/// **V4** — the fully live current shape (cloud-sync lot 0,
/// `docs/design-specs/2026-08-10-cloud-sync-design.md` §5.1). Adds three
/// stored properties — `updatedAt: Date`, `deletedAt: Date?`,
/// `syncedAt: Date?` — to each of the 8 **synchronized** entities per the
/// spec's §3 classification:
///
/// `UserProfile`, `Card`, `ReviewLog`, `RPGState`, `VocabularyEntry`,
/// `VocabularyEncounter`, `ExerciseOutcomeLog`, `CompanionChatMessage`.
///
/// `MnemonicCache` (regenerable cache), `AssetManifest` (device-local cache),
/// and `DailyTerm` (deterministic per day) are explicitly **not**
/// synchronized per spec §3 and gain no columns here.
///
/// This is schema-only: no repository writes `updatedAt` on mutation yet,
/// nothing reads `deletedAt`/`syncedAt` yet, and no network dependency is
/// introduced. See each model's doc comment for the "not wired yet" note.
///
/// `updatedAt` is non-optional with a property-level default of the Unix
/// epoch (`Date(timeIntervalSince1970: 0)`) so the `.lightweight` V3→V4
/// migration can backfill existing rows without a custom migration stage —
/// mirroring the `activeDaysCount: Int = 0` precedent from V1→V2, just for a
/// `Date`. Every model's initializer explicitly sets `updatedAt = Date()`
/// for freshly created objects, so only pre-existing (migrated) rows ever
/// see the epoch sentinel.
///
/// V4 uses *live* references throughout. **That is now a standing hazard, not
/// a neutral fact**: `IkeruSchemaV5` exists (2026-08-19) and V4 was NOT frozen
/// when it was cut, so V4 and V5 both describe whatever the live classes say
/// today. Adding, removing or retyping a stored property on any of these
/// classes silently rewrites what V4 means — the `aa03566` failure this file
/// opens with — and every real store stops hash-matching.
///
/// What holds the line until someone does the freeze: `IkeruSchemaTests`'
/// `v4GoldenFingerprint` (name list **and** typed digest) and
/// `v5GoldenFingerprint`. They fail loudly on any such edit. Do not "fix" them
/// by updating the golden values: freeze V4's touched entities into nested
/// snapshots the way V1 did, then cut V6.
public enum IkeruSchemaV4: VersionedSchema {

    public static var versionIdentifier: Schema.Version { Schema.Version(4, 0, 0) }

    public static var models: [any PersistentModel.Type] {
        [
            UserProfile.self,
            Card.self,
            ReviewLog.self,
            RPGState.self,
            MnemonicCache.self,
            CompanionChatMessage.self,
            AssetManifest.self,
            VocabularyEntry.self,
            VocabularyEncounter.self,
            DailyTerm.self,
            ExerciseOutcomeLog.self,
        ]
    }
}

// MARK: - Versioned Schema V5

/// **V5** — adds `TextImport`, the « apporte ton propre texte » entity.
///
/// Purely additive: one new entity, and **not a single existing model was
/// touched**. That was a design constraint, not luck. The natural modelling
/// hangs a relationship off `VocabularyEncounter` back to its import — and
/// `VocabularyEncounter` is referenced *live* by `IkeruSchemaV4`, so growing it
/// would have silently redefined what V4 means and reproduced the `aa03566`
/// failure this file opens with: every real store stops hash-matching and the
/// container refuses to open. `TextImport` carries the entry identifiers on its
/// own side instead (see its doc comment), so V4 keeps meaning exactly what it
/// meant and this stage stays `.lightweight`.
///
/// - Important: V4 is now frozen in the same sense as V1–V3 — its `models` list
///   names live types, so **any** future change to `VocabularyEncounter`,
///   `VocabularyEntry`, `Card`, `UserProfile` or `RPGState` must first pin a
///   nested snapshot into V4, exactly as V1 did.
public enum IkeruSchemaV5: VersionedSchema {

    public static var versionIdentifier: Schema.Version { Schema.Version(5, 0, 0) }

    public static var models: [any PersistentModel.Type] {
        [
            UserProfile.self,
            Card.self,
            ReviewLog.self,
            RPGState.self,
            MnemonicCache.self,
            CompanionChatMessage.self,
            AssetManifest.self,
            VocabularyEntry.self,
            VocabularyEncounter.self,
            DailyTerm.self,
            ExerciseOutcomeLog.self,
            TextImport.self,
        ]
    }
}

// MARK: - Migration Plan

/// The app's schema migration plan.
///
/// `IkeruSchemaV1` is the frozen shape released to TestFlight before
/// versioned schemas existed (see its doc comment for the full story);
/// `IkeruSchemaV2` is frozen at the shape that shipped before the
/// learner-telemetry `ReviewLog` fields; `IkeruSchemaV3` is frozen at the
/// shape that shipped before the cloud-sync columns; `IkeruSchemaV4` is the
/// live current shape. All three stages are purely additive — new
/// defaulted/optional columns and (for V1→V2) a wholly new entity — so
/// `.lightweight` is sufficient for each: SwiftData adds the new
/// columns/table and leaves prior data untouched.
///
/// When a future `@Model` change needs data transformation (renames with
/// data preservation, split/merge fields, etc.), use `.custom(...)` instead
/// of `.lightweight(...)` for that stage.
public enum IkeruMigrationPlan: SchemaMigrationPlan {

    public static var schemas: [any VersionedSchema.Type] {
        [IkeruSchemaV1.self, IkeruSchemaV2.self, IkeruSchemaV3.self,
         IkeruSchemaV4.self, IkeruSchemaV5.self]
    }

    public static var stages: [MigrationStage] {
        [
            .lightweight(fromVersion: IkeruSchemaV1.self, toVersion: IkeruSchemaV2.self),
            .lightweight(fromVersion: IkeruSchemaV2.self, toVersion: IkeruSchemaV3.self),
            .lightweight(fromVersion: IkeruSchemaV3.self, toVersion: IkeruSchemaV4.self),
            // V4 → V5 : une entité de plus (`TextImport`), rien de modifié.
            .lightweight(fromVersion: IkeruSchemaV4.self, toVersion: IkeruSchemaV5.self),
        ]
    }
}
