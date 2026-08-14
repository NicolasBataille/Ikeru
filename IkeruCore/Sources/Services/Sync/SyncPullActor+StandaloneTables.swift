import Foundation
import SwiftData

/// The 3 `SyncPullActor` apply functions for tables with no FK dependency
/// on `cards`/`review_logs` and no rule-2 replay involvement —
/// `vocabulary_entries`, `vocabulary_encounters`, `exercise_outcome_logs`.
/// Split out of `SyncPullActor.swift` itself purely to stay under
/// SwiftLint's `file_length` (1200 lines) and `type_body_length` (600
/// lines, actor body) budgets — there is no behavioral reason these three
/// couldn't live in the main file; `SyncPullActor.apply(table:rows:...)`
/// dispatches to them exactly like the other 4. See `fetchOne`'s doc
/// comment in `SyncPullActor.swift` for why it's `internal`, not `private`,
/// specifically so this file can still call it.
extension SyncPullActor {

    // MARK: - vocabulary_entries

    private struct VocabularyEntryPayload: Decodable {
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

    /// No rule-2 equivalent here — `VocabularyEntry` has no append-only log
    /// to replay from (see `SyncPayloadBuilder`'s doc comment on that
    /// table), so this is a plain rule-4 (tombstone-aware LWW) apply.
    func applyVocabularyEntryRows(_ rows: [SyncRow]) throws -> (count: Int, appliedFlags: [Bool]) {
        var applied = 0
        var appliedFlags: [Bool] = []
        appliedFlags.reserveCapacity(rows.count)
        for row in rows {
            // `try?` on the decode (CRITIQUE 2) — see `SyncPullActor.applyProfileRows`.
            guard let common = try? SyncRowDecoding.common(row),
                  let payloadValue = row["payload"],
                  let payload = try? SyncRowDecoding.decode(VocabularyEntryPayload.self, from: payloadValue) else {
                appliedFlags.append(false)
                continue
            }

            if let existing = try fetchOne(VocabularyEntry.self, id: common.id) {
                let winner = SyncMergeRules.resolveWinner(
                    local: .init(updatedAt: existing.updatedAt, deletedAt: existing.deletedAt),
                    remote: .init(updatedAt: common.updatedAt, deletedAt: common.deletedAt)
                )
                if winner == .remote {
                    existing.word = payload.word
                    existing.reading = payload.reading
                    existing.meaning = payload.meaning
                    existing.jlptLevelRawValue = payload.jlptLevel
                    existing.fsrsState = payload.fsrsState
                    existing.easeFactor = payload.easeFactor
                    existing.interval = payload.interval
                    existing.dueDate = payload.dueDate
                    existing.lapseCount = payload.lapseCount
                    existing.isInDictionary = payload.isInDictionary
                    existing.updatedAt = common.updatedAt
                    existing.deletedAt = common.deletedAt
                    existing.syncedAt = common.updatedAt
                }
            } else {
                let entry = VocabularyEntry(
                    word: payload.word,
                    reading: payload.reading,
                    meaning: payload.meaning,
                    jlptLevel: payload.jlptLevel.flatMap(JLPTLevel.init(rawValue:)),
                    isInDictionary: payload.isInDictionary,
                    fsrsState: payload.fsrsState,
                    easeFactor: payload.easeFactor,
                    interval: payload.interval,
                    dueDate: payload.dueDate,
                    lapseCount: payload.lapseCount,
                    createdAt: payload.createdAt
                )
                entry.id = common.id
                entry.updatedAt = common.updatedAt
                entry.deletedAt = common.deletedAt
                entry.syncedAt = common.updatedAt
                modelContext.insert(entry)
            }
            applied += 1
            appliedFlags.append(true)
        }
        return (applied, appliedFlags)
    }

    // MARK: - vocabulary_encounters

    private struct VocabularyEncounterPayload: Decodable {
        let source: String
    }

    func applyVocabularyEncounterRows(_ rows: [SyncRow]) throws -> (count: Int, appliedFlags: [Bool]) {
        var applied = 0
        var appliedFlags: [Bool] = []
        appliedFlags.reserveCapacity(rows.count)
        for row in rows {
            guard let common = try? SyncRowDecoding.common(row),
                  let payloadValue = row["payload"] else {
                appliedFlags.append(false)
                continue
            }

            // Append-only, same reasoning as `SyncPullActor.applyReviewLogRows`.
            if try fetchOne(VocabularyEncounter.self, id: common.id) != nil {
                applied += 1
                appliedFlags.append(true)
                continue
            }

            guard let entryID = SyncRowDecoding.uuid(row, "entry_id"),
                  let entry = try fetchOne(VocabularyEntry.self, id: entryID) else {
                appliedFlags.append(false)
                continue
            }
            guard let payload = try? SyncRowDecoding.decode(VocabularyEncounterPayload.self, from: payloadValue),
                  let timestamp = SyncRowDecoding.date(row, "occurred_at") else {
                appliedFlags.append(false)
                continue
            }

            // `contextSnippet` is never pushed (see `SyncPayloadBuilder`'s
            // trailing comment on this table) — a pulled encounter has no
            // snippet to restore, so it's left empty rather than fabricated.
            let encounter = VocabularyEncounter(
                source: EncounterSource(rawValue: payload.source) ?? .sakuraChat,
                contextSnippet: "",
                entry: entry,
                timestamp: timestamp
            )
            encounter.id = common.id
            encounter.updatedAt = common.updatedAt
            encounter.deletedAt = common.deletedAt
            encounter.syncedAt = common.updatedAt
            modelContext.insert(encounter)
            applied += 1
            appliedFlags.append(true)
        }
        return (applied, appliedFlags)
    }

    // MARK: - exercise_outcome_logs

    private struct ExerciseOutcomeLogPayload: Decodable {
        let skill: String
        let accuracy: Double
    }

    func applyExerciseOutcomeLogRows(_ rows: [SyncRow]) throws -> (count: Int, appliedFlags: [Bool]) {
        var applied = 0
        var appliedFlags: [Bool] = []
        appliedFlags.reserveCapacity(rows.count)
        for row in rows {
            guard let common = try? SyncRowDecoding.common(row),
                  let payloadValue = row["payload"] else {
                appliedFlags.append(false)
                continue
            }

            // Append-only, same reasoning as `SyncPullActor.applyReviewLogRows`.
            if try fetchOne(ExerciseOutcomeLog.self, id: common.id) != nil {
                applied += 1
                appliedFlags.append(true)
                continue
            }

            guard let profileID = SyncRowDecoding.uuid(row, "profile_id"),
                  let timestamp = SyncRowDecoding.date(row, "occurred_at"),
                  let payload = try? SyncRowDecoding.decode(ExerciseOutcomeLogPayload.self, from: payloadValue) else {
                appliedFlags.append(false)
                continue
            }

            let log = ExerciseOutcomeLog(
                skill: SkillType(rawValue: payload.skill) ?? .listening,
                accuracy: payload.accuracy,
                profileID: profileID,
                timestamp: timestamp
            )
            log.id = common.id
            log.updatedAt = common.updatedAt
            log.deletedAt = common.deletedAt
            log.syncedAt = common.updatedAt
            modelContext.insert(log)
            applied += 1
            appliedFlags.append(true)
        }
        return (applied, appliedFlags)
    }
}
