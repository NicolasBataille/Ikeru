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
/// Models that cannot reach `RPGState` through any relationship
/// (`MnemonicCache`, `CompanionChatMessage`, `AssetManifest`,
/// `VocabularyEntry`, `VocabularyEncounter`, `DailyTerm`) stay live
/// references: freezing them buys no additional safety (they can't drift via
/// this relationship graph) while multiplying the maintenance burden every
/// future versioned schema would carry forward.
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
        // 19-property shapes; if this list is ever moved out of the enum body,
        // those tests fail before anything ships.
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
}

// MARK: - Versioned Schema V2

/// **V2** — the fully live current shape. Two additive changes on top of V1:
///
/// 1. `RPGState.activeDaysCount` (commit `aa03566`) — a new stored `Int`
///    property, defaulting to `0`. This is the property whose addition to
///    the *live* `RPGState` class silently mutated `IkeruSchemaV1`'s meaning
///    before V1 was frozen (see the post-mortem in `IkeruSchemaV1`'s doc
///    comment); it is only ever meant to exist from V2 onward.
/// 2. `ExerciseOutcomeLog` (remediation 4.4) — a brand-new entity whose only
///    cross-entity reference is a scalar `profileID: UUID` (not a SwiftData
///    relationship), so it doesn't change any existing entity's shape.
///
/// Both changes are lightweight-safe: an added scalar property with a
/// default, and a wholly new entity. Unlike V1, V2 uses *live* references
/// throughout — it doesn't need to be frozen because there is currently no
/// V3. The day a `V3` is created, V2 must be frozen the same way V1 was.
public enum IkeruSchemaV2: VersionedSchema {

    public static var versionIdentifier: Schema.Version { Schema.Version(2, 0, 0) }

    public static var models: [any PersistentModel.Type] {
        // The first four bind to the frozen nested snapshots below via name
        // shadowing. ⚠️ Do NOT "clarify" them to `IkeruSchemaV1.UserProfile.self`
        // etc.: self-qualifying the nested @Model types from inside this enum's
        // own body empirically breaks SwiftData's class↔entity resolution at
        // runtime ("Failed to cast model IkeruCore.UserProfile … to UserProfile"
        // in the migration tests) — bisected 2026-07-15. The golden fingerprint
        // tests in IkeruSchemaTests pin that these resolve to the frozen
        // 19-property shapes; if this list is ever moved out of the enum body,
        // those tests fail before anything ships.
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

// MARK: - Migration Plan

/// The app's schema migration plan.
///
/// `IkeruSchemaV1` is the frozen shape released to TestFlight before
/// versioned schemas existed (see its doc comment for the full story);
/// `IkeruSchemaV2` is the live current shape. The V1 → V2 delta —
/// `RPGState.activeDaysCount` (additive, defaulted) plus the wholly new
/// `ExerciseOutcomeLog` entity — touches no existing entity's identity or
/// required data, so a `.lightweight` stage is sufficient: SwiftData adds the
/// new column and the new table and leaves all V1 data untouched.
///
/// When a future `@Model` change needs data transformation (renames with
/// data preservation, split/merge fields, etc.), use `.custom(...)` instead
/// of `.lightweight(...)` for that stage.
public enum IkeruMigrationPlan: SchemaMigrationPlan {

    public static var schemas: [any VersionedSchema.Type] {
        [IkeruSchemaV1.self, IkeruSchemaV2.self]
    }

    public static var stages: [MigrationStage] {
        [.lightweight(fromVersion: IkeruSchemaV1.self, toVersion: IkeruSchemaV2.self)]
    }
}
