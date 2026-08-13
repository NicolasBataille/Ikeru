import Foundation

/// Builds one `SyncRow` per synced entity type, matching the live server
/// schema (verified via the Supabase MCP `list_tables` against project
/// `aiayzlarixlogcoyswna` during this task — column names below are not
/// guessed from the design doc's prose, which omits the `profile_id`/
/// `entry_id` foreign-key columns these tables actually carry).
///
/// `user_id` is never included: every table's `user_id` column
/// `default`s to `auth.uid()`, so omitting it is both simpler and the
/// RLS-safest choice (a client-supplied `user_id` that happened to
/// mismatch the bearer token would just be overwritten by the default —
/// but not sending it removes the possibility entirely).
enum SyncPayloadBuilder {

    // MARK: - profiles

    private struct ProfilePayload: Encodable {
        let displayName: String
        let createdAt: Date
        let settings: ProfileSettings
    }

    static func row(for profile: UserProfile) throws -> SyncRow {
        let payload = ProfilePayload(
            displayName: profile.displayName,
            createdAt: profile.createdAt,
            settings: profile.settings
        )
        return [
            "id": .uuid(profile.id),
            "payload": try SyncJSON.jsonValue(encoding: payload),
            "updated_at": .date(profile.updatedAt),
            "deleted_at": .dateOrNull(profile.deletedAt),
        ]
    }

    // MARK: - rpg_states

    private struct RPGStatePayload: Encodable {
        let xp: Int
        let level: Int
        let totalReviewsCompleted: Int
        let totalSessionsCompleted: Int
        let currentDailyStreak: Int
        let longestDailyStreak: Int
        let activeDaysCount: Int
        let lastSessionDate: Date?
    }

    static func row(for state: RPGState) throws -> SyncRow {
        let payload = RPGStatePayload(
            xp: state.xp,
            level: state.level,
            totalReviewsCompleted: state.totalReviewsCompleted,
            totalSessionsCompleted: state.totalSessionsCompleted,
            currentDailyStreak: state.currentDailyStreak,
            longestDailyStreak: state.longestDailyStreak,
            activeDaysCount: state.activeDaysCount,
            lastSessionDate: state.lastSessionDate
        )
        return [
            "id": .uuid(state.id),
            "profile_id": .uuidOrNull(state.profile?.id),
            "payload": try SyncJSON.jsonValue(encoding: payload),
            "updated_at": .date(state.updatedAt),
            "deleted_at": .dateOrNull(state.deletedAt),
        ]
    }

    // MARK: - cards

    private struct CardPayload: Encodable {
        let front: String
        let back: String
        let type: String
        let fsrsState: FSRSState
        let easeFactor: Double
        let interval: Int
        let dueDate: Date
        let lapseCount: Int
        let leechFlag: Bool
        let jlptLevel: String?
    }

    static func row(for card: Card) throws -> SyncRow {
        let payload = CardPayload(
            front: card.front,
            back: card.back,
            type: card.typeRawValue,
            fsrsState: card.fsrsState,
            easeFactor: card.easeFactor,
            interval: card.interval,
            dueDate: card.dueDate,
            lapseCount: card.lapseCount,
            leechFlag: card.leechFlag,
            jlptLevel: card.jlptLevelRawValue
        )
        return [
            "id": .uuid(card.id),
            "profile_id": .uuidOrNull(card.profile?.id),
            "payload": try SyncJSON.jsonValue(encoding: payload),
            "updated_at": .date(card.updatedAt),
            "deleted_at": .dateOrNull(card.deletedAt),
        ]
    }

    // MARK: - review_logs

    private struct ReviewLogPayload: Encodable {
        let responseTimeMs: Int
    }

    static func row(for log: ReviewLog) throws -> SyncRow {
        let payload = ReviewLogPayload(responseTimeMs: log.responseTimeMs)
        return [
            "id": .uuid(log.id),
            "card_id": .uuidOrNull(log.card?.id),
            "occurred_at": .date(log.timestamp),
            "grade": .number(Double(log.gradeRawValue)),
            "answered_value": .stringOrNull(log.answeredValue),
            "exercise_type": .stringOrNull(log.exerciseType),
            "surface": .stringOrNull(log.surface),
            "payload": try SyncJSON.jsonValue(encoding: payload),
            "updated_at": .date(log.updatedAt),
            "deleted_at": .dateOrNull(log.deletedAt),
        ]
    }

    // MARK: - vocabulary_entries

    private struct VocabularyEntryPayload: Encodable {
        let word: String
        let reading: String
        let meaning: String
        let jlptLevel: String?
        let fsrsState: FSRSState
        let easeFactor: Double
        let interval: Int
        let dueDate: Date
        let lapseCount: Int
        let isInDictionary: Bool
        let createdAt: Date
    }

    /// `profile_id` is always pushed `.null` for this table: unlike `Card`
    /// / `RPGState`, the live `VocabularyEntry` model (see
    /// `Sources/Models/Vocabulary/VocabularyEntry.swift`) carries no
    /// `profile` relationship at all — there is nothing to read here. Adding
    /// one is a model change outside this lot's file perimeter (and outside
    /// the "no SwiftData schema change" rule); pushing a fabricated value
    /// instead of `null` would be worse. Declared, not silently omitted.
    static func row(for entry: VocabularyEntry) throws -> SyncRow {
        let payload = VocabularyEntryPayload(
            word: entry.word,
            reading: entry.reading,
            meaning: entry.meaning,
            jlptLevel: entry.jlptLevelRawValue,
            fsrsState: entry.fsrsState,
            easeFactor: entry.easeFactor,
            interval: entry.interval,
            dueDate: entry.dueDate,
            lapseCount: entry.lapseCount,
            isInDictionary: entry.isInDictionary,
            createdAt: entry.createdAt
        )
        return [
            "id": .uuid(entry.id),
            "profile_id": .null,
            "payload": try SyncJSON.jsonValue(encoding: payload),
            "updated_at": .date(entry.updatedAt),
            "deleted_at": .dateOrNull(entry.deletedAt),
        ]
    }

    // MARK: - vocabulary_encounters

    // `contextSnippet` is deliberately absent. It holds the sentence the word
    // was met in — and when the source is Sakura, that sentence is free-form
    // text the learner typed or the model wrote back to them. Pushing it would
    // route conversation content to the server through the vocabulary table,
    // side-stepping the separate opt-in that companion_chat_messages is held
    // back for. The source alone carries the pedagogical signal (where the
    // encounter happened); the snippet is a local reading aid.
    private struct VocabularyEncounterPayload: Encodable {
        let source: String
    }

    static func row(for encounter: VocabularyEncounter) throws -> SyncRow {
        let payload = VocabularyEncounterPayload(
            source: encounter.sourceRawValue
        )
        return [
            "id": .uuid(encounter.id),
            "entry_id": .uuidOrNull(encounter.entry?.id),
            "occurred_at": .date(encounter.timestamp),
            "payload": try SyncJSON.jsonValue(encoding: payload),
            "updated_at": .date(encounter.updatedAt),
            "deleted_at": .dateOrNull(encounter.deletedAt),
        ]
    }

    // MARK: - exercise_outcome_logs

    private struct ExerciseOutcomeLogPayload: Encodable {
        let skill: String
        let accuracy: Double
    }

    static func row(for log: ExerciseOutcomeLog) throws -> SyncRow {
        let payload = ExerciseOutcomeLogPayload(skill: log.skillRawValue, accuracy: log.accuracy)
        return [
            "id": .uuid(log.id),
            "profile_id": .uuid(log.profileID),
            "occurred_at": .date(log.timestamp),
            "payload": try SyncJSON.jsonValue(encoding: payload),
            "updated_at": .date(log.updatedAt),
            "deleted_at": .dateOrNull(log.deletedAt),
        ]
    }

    // MARK: - companion_chat_messages
    //
    // Deliberately NOT built here. `CompanionChatMessage.content` is
    // free-form text the learner typed to Sakura — design spec §5.4 / §7 and
    // this task's item 4 require a SEPARATE opt-in before any of it leaves
    // the device, distinct from the general cloud-sync toggle this lot
    // implements. That second opt-in does not exist yet, so this lot must
    // not push this table at all — see `CloudSyncCoordinator.syncNow()`,
    // which never calls a row builder for this entity.
}
