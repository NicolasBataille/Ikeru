import Foundation
import SwiftData

/// The 4 `SyncPullActor` apply functions for tables with no FK dependency
/// on `cards`/`review_logs` and no rule-2 replay involvement —
/// `vocabulary_entries`, `vocabulary_encounters`, `exercise_outcome_logs`,
/// `text_imports`.
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
    func applyVocabularyEntryRows(_ rows: [SyncRow]) throws -> (count: Int, outcomes: [RowApplyOutcome]) {
        var applied = 0
        var outcomes: [RowApplyOutcome] = []
        outcomes.reserveCapacity(rows.count)
        for row in rows {
            // `try?` on the decode (CRITIQUE 2) — see `SyncPullActor.applyProfileRows`.
            // Always PERMANENT — `vocabulary_entries` has no foreign key of
            // its own to wait on (see `RowApplyOutcome`).
            guard let common = try? SyncRowDecoding.common(row),
                  let payloadValue = row["payload"],
                  let payload = try? SyncRowDecoding.decode(VocabularyEntryPayload.self, from: payloadValue) else {
                outcomes.append(.skippedPermanent)
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
            outcomes.append(.applied)
        }
        return (applied, outcomes)
    }

    // MARK: - vocabulary_encounters

    private struct VocabularyEncounterPayload: Decodable {
        let source: String
    }

    func applyVocabularyEncounterRows(_ rows: [SyncRow]) throws -> (count: Int, outcomes: [RowApplyOutcome], alreadyPresentCount: Int) {
        var applied = 0
        var alreadyPresent = 0
        var outcomes: [RowApplyOutcome] = []
        outcomes.reserveCapacity(rows.count)
        for row in rows {
            // PERMANENT — the row itself is undecodable, not waiting on
            // anything.
            guard let common = try? SyncRowDecoding.common(row),
                  let payloadValue = row["payload"] else {
                outcomes.append(.skippedPermanent)
                continue
            }

            // Append-only, same reasoning as `SyncPullActor.applyReviewLogRows`
            // — including counting a redelivery in `alreadyPresent`, not
            // `applied` (see `PullSummary.alreadyPresentRowCounts`).
            if let existing = try fetchOne(VocabularyEncounter.self, id: common.id) {
                // …except a tombstone, which is the one field an append-only
                // row can legitimately gain later. See the equivalent branch
                // in `SyncPullActor.applyReviewLogRows` for the full story
                // and the two-container reproduction. Only nil → non-nil.
                if existing.deletedAt == nil, let remoteDeletedAt = common.deletedAt {
                    existing.deletedAt = remoteDeletedAt
                    existing.updatedAt = max(existing.updatedAt, common.updatedAt)
                    existing.syncedAt = common.updatedAt
                }
                alreadyPresent += 1
                outcomes.append(.applied)
                continue
            }

            guard let entryID = SyncRowDecoding.uuid(row, "entry_id"),
                  let entry = try fetchOne(VocabularyEntry.self, id: entryID) else {
                // TRANSIENT — the referenced `vocabulary_entries` row isn't
                // locally present YET (same "wait, don't abandon" reasoning
                // as `applyReviewLogRows`' card lookup — `vocabulary_entries`
                // is pulled before `vocabulary_encounters` in `pullOrder`,
                // but the entry can itself be delayed).
                outcomes.append(.skippedTransient)
                continue
            }
            // PERMANENT — the FK resolved; what's left undecodable here is
            // the row's own content.
            guard let payload = try? SyncRowDecoding.decode(VocabularyEncounterPayload.self, from: payloadValue),
                  let timestamp = SyncRowDecoding.date(row, "occurred_at") else {
                outcomes.append(.skippedPermanent)
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
            outcomes.append(.applied)
        }
        return (applied, outcomes, alreadyPresent)
    }

    // MARK: - exercise_outcome_logs

    private struct ExerciseOutcomeLogPayload: Decodable {
        let skill: String
        let accuracy: Double
    }

    func applyExerciseOutcomeLogRows(_ rows: [SyncRow]) throws -> (count: Int, outcomes: [RowApplyOutcome], alreadyPresentCount: Int) {
        var applied = 0
        var alreadyPresent = 0
        var outcomes: [RowApplyOutcome] = []
        outcomes.reserveCapacity(rows.count)
        for row in rows {
            // PERMANENT — the row itself is undecodable, not waiting on
            // anything.
            guard let common = try? SyncRowDecoding.common(row),
                  let payloadValue = row["payload"] else {
                outcomes.append(.skippedPermanent)
                continue
            }

            // Append-only, same reasoning as `SyncPullActor.applyReviewLogRows`
            // — including counting a redelivery in `alreadyPresent`, not
            // `applied` (see `PullSummary.alreadyPresentRowCounts`).
            if let existing = try fetchOne(ExerciseOutcomeLog.self, id: common.id) {
                // …except a tombstone — same exception, same reasoning as
                // `SyncPullActor.applyReviewLogRows`. Only nil → non-nil.
                if existing.deletedAt == nil, let remoteDeletedAt = common.deletedAt {
                    existing.deletedAt = remoteDeletedAt
                    existing.updatedAt = max(existing.updatedAt, common.updatedAt)
                    existing.syncedAt = common.updatedAt
                }
                alreadyPresent += 1
                outcomes.append(.applied)
                continue
            }

            // `profile_id` here is a SCALAR field on the row (`ExerciseOutcomeLog.profileID`
            // is not a SwiftData relationship — see that model's doc
            // comment), not a local-entity lookup — a missing/unparseable
            // value is a decode failure of THIS row, not a reference to
            // something that hasn't arrived yet. Always PERMANENT,
            // unlike `applyReviewLogRows`'/`applyVocabularyEncounterRows`'
            // FK lookups.
            guard let profileID = SyncRowDecoding.uuid(row, "profile_id"),
                  let timestamp = SyncRowDecoding.date(row, "occurred_at"),
                  let payload = try? SyncRowDecoding.decode(ExerciseOutcomeLogPayload.self, from: payloadValue) else {
                outcomes.append(.skippedPermanent)
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
            outcomes.append(.applied)
        }
        return (applied, outcomes, alreadyPresent)
    }
    // MARK: - text_imports

    /// Rule-4 (tombstone-aware LWW) apply, modelled on
    /// `applyVocabularyEntryRows` rather than on the append-only tables above.
    ///
    /// Two things that look like they should be copied from
    /// `applyVocabularyEncounterRows`, and deliberately are not:
    ///
    /// - **No `.skippedTransient` branch.** A `TextImport` carries its
    ///   vocabulary links as *scalar* `entryIDs`, not as a SwiftData
    ///   relationship — that was the whole point of putting them on this side
    ///   (see `TextImport`'s doc comment: growing `VocabularyEncounter` would
    ///   have silently redefined `IkeruSchemaV4`). There is no foreign key to
    ///   wait on, so every skip here is PERMANENT. An identifier pointing at
    ///   an entry this device doesn't have is not a reason to withhold the
    ///   learner's text.
    /// - **No `alreadyPresentCount`.** This table is not append-only: an
    ///   import can gain entries, and `TextImportRepository.delete(_:)`
    ///   tombstones it. A redelivered row goes through the normal merge, like
    ///   `vocabulary_entries`.
    func applyTextImportRows(_ rows: [SyncRow]) throws -> (count: Int, outcomes: [RowApplyOutcome]) {
        var applied = 0
        var outcomes: [RowApplyOutcome] = []
        outcomes.reserveCapacity(rows.count)
        for row in rows {
            // `coverage` is READ but not guarded: `nil` is a legal value (the
            // text held nothing measurable to count), so a missing cell maps
            // straight through rather than disqualifying the row. Everything
            // else is required — a text without its content is not worth
            // restoring.
            guard let common = try? SyncRowDecoding.common(row),
                  let title = SyncRowDecoding.string(row, "title"),
                  let content = SyncRowDecoding.string(row, "content"),
                  let sourceRawValue = SyncRowDecoding.string(row, "source"),
                  let createdAt = SyncRowDecoding.date(row, "created_at"),
                  let entryIDs = SyncRowDecoding.uuidArray(row, "entry_ids") else {
                outcomes.append(.skippedPermanent)
                continue
            }
            let coverage = SyncRowDecoding.number(row, "coverage")

            if let existing = try fetchOne(TextImport.self, id: common.id) {
                let winner = SyncMergeRules.resolveWinner(
                    local: .init(updatedAt: existing.updatedAt, deletedAt: existing.deletedAt),
                    remote: .init(updatedAt: common.updatedAt, deletedAt: common.deletedAt)
                )
                if winner == .remote {
                    existing.title = title
                    existing.content = content
                    // `sourceRawValue`, not `source` — an unrecognised value
                    // written by a newer app version survives verbatim instead
                    // of being rewritten to `.paste` by the enum's fallback.
                    existing.sourceRawValue = sourceRawValue
                    existing.createdAt = createdAt
                    existing.coverage = coverage
                    existing.entryIDs = entryIDs
                    existing.updatedAt = common.updatedAt
                    existing.deletedAt = common.deletedAt
                    existing.syncedAt = common.updatedAt
                }
            } else {
                let record = TextImport(
                    id: common.id,
                    title: title,
                    content: content,
                    source: ImportSource(rawValue: sourceRawValue) ?? .paste,
                    createdAt: createdAt,
                    coverage: coverage,
                    entryIDs: entryIDs
                )
                // Both re-asserted AFTER the initializer, which is not a
                // pass-through: it re-derives the title from the first line
                // when the one it is given is empty, and it stores the enum
                // case rather than the raw string. Neither is wanted on a
                // restore — the server's values are what the learner's own
                // device produced, and re-deriving them here would let two
                // devices disagree about the same import, or quietly rewrite
                // a `source` a newer app version wrote.
                record.title = title
                record.sourceRawValue = sourceRawValue
                record.updatedAt = common.updatedAt
                record.deletedAt = common.deletedAt
                record.syncedAt = common.updatedAt
                modelContext.insert(record)
            }
            applied += 1
            outcomes.append(.applied)
        }
        return (applied, outcomes)
    }
}
