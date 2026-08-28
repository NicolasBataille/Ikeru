import Foundation
import SwiftData
import IkeruCore
import os

// MARK: - DataExportManager

/// Exports learning data in JSON and CSV formats for AI agent analysis.
/// Generates a structured export bundle (zipped into a single `.zip` for
/// sharing) with a context.json describing the data model.
@MainActor
final class DataExportManager {

    // MARK: - Export

    /// Generates a complete data export as a single `.zip` archive and returns
    /// its temporary URL. The archive contains: cards.json, reviews.json,
    /// confusions.json, outcomes.json, rpg.json, context.json, cards.csv.
    ///
    /// The intermediate export directory is zipped (so the share sheet hands the
    /// user one file, not a bare folder) and then deleted. A serialization or
    /// archiving failure throws — nothing partial is ever shared.
    func exportData(modelContainer: ModelContainer) async throws -> URL {
        let exportDir = try await buildExportDirectory(modelContainer: modelContainer)
        defer { try? FileManager.default.removeItem(at: exportDir) }

        // Zipping is blocking file I/O — run it off the main actor so a large
        // export never hitches the UI. `zipDirectory` is a `nonisolated static`
        // function touching only `FileManager`/`NSFileCoordinator`, so it is
        // safe to invoke from a detached task.
        let zipURL = try await Task.detached(priority: .utility) {
            try Self.zipDirectory(exportDir)
        }.value
        Logger.ui.info("Data export archived at \(zipURL.path)")
        return zipURL
    }

    /// Writes every export file into a fresh temporary directory and returns it.
    /// Factored out of `exportData` so the file contents can be validated
    /// independently of the archiving step.
    ///
    /// SwiftData access (cards, review logs, RPG state) happens here on the
    /// MainActor and is converted to Sendable value types immediately. The
    /// heavy work — JSON encoding, CSV generation, and file writes — then runs
    /// off the main actor inside a detached task, so encoding a large review
    /// history never hitches the UI.
    func buildExportDirectory(modelContainer: ModelContainer) async throws -> URL {
        let context = modelContainer.mainContext

        // Cards + review logs — CardRepository already fetches on a background
        // ModelActor and hands back Sendable DTOs (CardDTO / ReviewLogDTO).
        let cardRepo = CardRepository(modelContainer: modelContainer)
        let allCards = await cardRepo.allCards()

        // Review logs — scoped to the ACTIVE PROFILE only. The export leaves
        // the device, so it must never bundle another profile's review
        // history. Empty history still writes a valid `[]` rather than
        // omitting the file.
        let reviewLogs = await cardRepo.activeProfileReviewLogs()

        // Exercise outcomes (listening / shadowing drills with no backing
        // Card) — scoped to the ACTIVE PROFILE only, exactly like
        // reviews.json above. Empty history still writes a valid `[]`.
        let exerciseOutcomes = await cardRepo.activeProfileExerciseOutcomes()

        // RPG state — scoped to the ACTIVE PROFILE only (the export leaves
        // the device, so it must never leak another profile's progression,
        // exactly like the reviews.json scoping above).
        //
        // Deliberately reads `profile.rpgState` directly rather than calling
        // `ActiveProfileResolver.fetchActiveRPGState(in:)`: that helper
        // lazily creates *and saves* a new RPGState for a profile that
        // predates one, and an export must never mutate persisted state the
        // user didn't ask for. This read-only lookup preserves the original
        // "omit rpg.json if no RPG state exists" behavior without ever
        // calling `context.save()`. The extraction happens synchronously on
        // the MainActor, converting the non-Sendable `RPGState` model into
        // the Sendable `RPGExport` value type before anything crosses an
        // isolation boundary.
        var rpgExport: RPGExport?
        if let profile = ActiveProfileResolver.fetchActiveProfile(in: context),
            let rpg = profile.rpgState {
            // "Lifetime review count" (see the label in `writeContextJSON`)
            // comes from `ReviewLog` (GAP-13), not `rpg.totalReviewsCompleted`
            // — that field's hand-incremented writers can undercount against
            // the real review history (the kana drill never touches it at
            // all), so an export taken by a learner who also uses the drill
            // would otherwise ship a number visibly smaller than the review
            // count in reviews.json above. See `RPGState.totalReviewsCompleted`'s
            // doc comment for the full list of writers.
            let totalReviews = await cardRepo.activeProfileReviewCount()
            rpgExport = RPGExport(
                xp: rpg.xp,
                level: rpg.level,
                totalReviewsCompleted: totalReviews,
                totalSessionsCompleted: rpg.totalSessionsCompleted,
                attributes: rpg.attributes,
                inventoryCount: rpg.lootInventory.count,
                unopenedLootBoxes: rpg.unopenedLootBoxes.count
            )
        }

        // Only Sendable value types (CardDTO, ReviewLogDTO,
        // ExerciseOutcomeLogDTO, RPGExport) cross into the detached task below
        // — no ModelContext, ModelContainer, or @Model instance is ever
        // captured off the main actor.
        let exportDir = try await Task.detached(priority: .utility) {
            try Self.writeExportFiles(
                cards: allCards,
                reviews: reviewLogs,
                outcomes: exerciseOutcomes,
                rpg: rpgExport
            )
        }.value

        Logger.ui.info("Data export written to \(exportDir.path)")
        return exportDir
    }

    // MARK: - Off-main writing

    /// Builds a fresh temporary directory and writes every export file into
    /// it: cards.json, cards.csv, reviews.json, confusions.json, outcomes.json,
    /// rpg.json (if present), and context.json. Runs off the main actor — only
    /// Sendable inputs (`CardDTO`, `ReviewLogDTO`, `ExerciseOutcomeLogDTO`,
    /// `RPGExport`) are accepted.
    ///
    /// `confusions.json` is derived, not persisted: it is aggregated from
    /// `reviews` + `cards` right here, at export time (learner-telemetry lot 1,
    /// see `docs/design-specs/2026-08-10-learner-telemetry-design.md` §3.1/§4).
    nonisolated private static func writeExportFiles(
        cards: [CardDTO],
        reviews: [ReviewLogDTO],
        outcomes: [ExerciseOutcomeLogDTO],
        rpg: RPGExport?
    ) throws -> URL {
        let exportDir = FileManager.default.temporaryDirectory
            .appending(path: "ikeru-export-\(Date().timeIntervalSince1970)", directoryHint: .isDirectory)

        try FileManager.default.createDirectory(at: exportDir, withIntermediateDirectories: true)
        // Clean up the partial directory if any subsequent write throws: the
        // caller only ever cleans up the returned URL, and on failure it never
        // receives one. `succeeded` flips true only after every file is written.
        var succeeded = false
        defer { if !succeeded { try? FileManager.default.removeItem(at: exportDir) } }

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        // Cards
        let cardsData = try encoder.encode(cards.map { CardExportRow(from: $0) })
        try cardsData.write(to: exportDir.appending(path: "cards.json"))

        // Cards CSV
        let csv = generateCardsCSV(cards: cards)
        try csv.write(to: exportDir.appending(path: "cards.csv"), atomically: true, encoding: .utf8)

        // Review logs
        let reviewsData = try encoder.encode(reviews.map { ReviewExportRow(from: $0) })
        try reviewsData.write(to: exportDir.appending(path: "reviews.json"))

        // Confusion pairs — DERIVED from reviews + cards, nothing new persisted.
        // Always written (an empty `[]` when there is no confusable history yet),
        // matching the "empty history still writes a valid file" convention used
        // by reviews.json/outcomes.json above.
        let confusionsData = try encoder.encode(generateConfusions(cards: cards, reviews: reviews))
        try confusionsData.write(to: exportDir.appending(path: "confusions.json"))

        // Exercise outcomes (listening / shadowing, no backing Card)
        let outcomesData = try encoder.encode(outcomes.map { OutcomeExportRow(from: $0) })
        try outcomesData.write(to: exportDir.appending(path: "outcomes.json"))

        // RPG state — omitted entirely when the active profile has none.
        if let rpg {
            try encoder.encode(rpg).write(to: exportDir.appending(path: "rpg.json"))
        }

        // Context file (data model documentation)
        let contextJSON = generateContextJSON()
        try contextJSON.write(
            to: exportDir.appending(path: "context.json"),
            atomically: true,
            encoding: .utf8
        )

        succeeded = true
        return exportDir
    }

    // MARK: - Archiving

    /// Zips a directory into a sibling `.zip` file using `NSFileCoordinator`'s
    /// `.forUploading` reading intent — the system-provided, dependency-free way
    /// to produce a zip of a folder. The coordinator hands back a temporary
    /// archive that is only valid inside the accessor closure, so it is moved to
    /// a stable location before returning.
    ///
    /// `nonisolated static` so it can run off the main actor: it touches no
    /// actor-isolated state, only `FileManager`/`NSFileCoordinator`.
    nonisolated private static func zipDirectory(_ directory: URL) throws -> URL {
        let coordinator = NSFileCoordinator()
        var coordinatorError: NSError?
        var moveError: Error?
        var producedURL: URL?

        let destination = directory.deletingLastPathComponent()
            .appending(path: directory.lastPathComponent + ".zip")
        try? FileManager.default.removeItem(at: destination)

        coordinator.coordinate(
            readingItemAt: directory,
            options: [.forUploading],
            error: &coordinatorError
        ) { temporaryZipURL in
            do {
                try FileManager.default.moveItem(at: temporaryZipURL, to: destination)
                producedURL = destination
            } catch {
                moveError = error
            }
        }

        // If the coordinator reported an error even after the move succeeded,
        // don't leave the moved archive orphaned at `destination`.
        if let coordinatorError {
            try? FileManager.default.removeItem(at: destination)
            throw coordinatorError
        }
        if let moveError { throw moveError }
        guard let producedURL else { throw ExportError.archivingFailed }
        return producedURL
    }

    // MARK: - Cleanup

    /// Deletes the temporary export artifact (the `.zip`). Call after the share
    /// sheet is dismissed.
    func cleanup(url: URL) {
        try? FileManager.default.removeItem(at: url)
        Logger.ui.info("Cleaned up export artifact at \(url.path)")
    }

    // MARK: - CSV Generation

    nonisolated private static func generateCardsCSV(cards: [CardDTO]) -> String {
        // `ease_factor` remplacé par le véritable état FSRS (OBS2-038).
        // `easeFactor` est un vestige SM-2 que rien n'écrit jamais : il vaut
        // 2.5 sur toutes les cartes depuis toujours. Exporté sous l'étiquette
        // « état d'ordonnancement courant », il donnait à qui migre vers Anki
        // un planning faux — une constante décorative présentée comme donnée.
        var csv = "id,front,back,type,due_date,difficulty,stability,interval,reps,lapse_count,leech_flag\n"
        let dateFormatter = ISO8601DateFormatter()

        for card in cards {
            let row = [
                card.id.uuidString,
                escapeCSV(card.front),
                escapeCSV(card.back),
                card.type.rawValue,
                dateFormatter.string(from: card.dueDate),
                String(format: "%.4f", card.fsrsState.difficulty),
                String(format: "%.4f", card.fsrsState.stability),
                "\(card.interval)",
                "\(card.fsrsState.reps)",
                "\(card.lapseCount)",
                "\(card.leechFlag)",
            ]
            csv += row.joined(separator: ",") + "\n"
        }
        return csv
    }

    // MARK: - Confusion Pair Aggregation

    /// Aggregates `(expected, answered)` character pairs from `reviews` into
    /// occurrence counts. `expected` is the reviewed card's `front` (looked up
    /// by `cardId`); `answered` is `ReviewLogDTO.answeredValue`.
    ///
    /// A row is included only when:
    /// - `cardId` is non-nil (the card wasn't deleted, so `front` is
    ///   resolvable) and matches a card in `cards`;
    /// - `answeredValue` is non-nil (the exercise format recorded a choice —
    ///   today, only the kana quiz does; self-graded flashcards never set it);
    /// - `expected != answered` — a **correct** answer isn't a confusion, and
    ///   inflating this file with matches would bury the pairs that matter.
    ///   Per-item accuracy is already visible in `reviews.json`.
    ///
    /// Sorted by count descending, then `expected`/`answered` ascending, so the
    /// output (and any test asserting on it) is deterministic regardless of
    /// dictionary iteration order.
    nonisolated private static func generateConfusions(
        cards: [CardDTO],
        reviews: [ReviewLogDTO]
    ) -> [ConfusionExportRow] {
        let frontByCardId = Dictionary(uniqueKeysWithValues: cards.map { ($0.id, $0.front) })

        var counts: [ConfusionPairKey: Int] = [:]
        for review in reviews {
            guard let cardId = review.cardId,
                let answered = review.answeredValue,
                let expected = frontByCardId[cardId],
                expected != answered
            else { continue }
            counts[ConfusionPairKey(expected: expected, answered: answered), default: 0] += 1
        }

        return counts
            .map { ConfusionExportRow(expected: $0.key.expected, answered: $0.key.answered, count: $0.value) }
            .sorted { lhs, rhs in
                if lhs.count != rhs.count { return lhs.count > rhs.count }
                if lhs.expected != rhs.expected { return lhs.expected < rhs.expected }
                return lhs.answered < rhs.answered
            }
    }

    nonisolated private static func escapeCSV(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") {
            return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return value
    }

    // MARK: - Context JSON

    nonisolated private static func generateContextJSON() -> String {
        // swiftlint:disable line_length
        // The lines below are prose describing the exported schema for external
        // consumers (data scientists, other tools) — kept as single JSON string
        // values on purpose so they stay easy to grep/diff. Wrapping mid-sentence
        // would either break JSON validity (a raw newline inside a JSON string
        // isn't valid without an escaped \n) or require splitting one field's
        // meaning across several JSON keys, which is worse for a reader of the
        // exported context.json than one long line is for a reader of this file.
        """
        {
          "export_format": "ikeru-v1",
          "description": "Ikeru Japanese learning app data export",
          "files": {
            "cards.json": {
              "description": "All SRS flashcards with their current scheduling state",
              "fields": {
                "id": "UUID — unique card identifier",
                "front": "The question/prompt (kanji, kana, or vocabulary)",
                "back": "The answer (reading, meaning, or translation)",
                "type": "Card category: kanji, vocabulary, grammar, listening",
                "dueDate": "ISO8601 date when the card is next due for review",
                "difficulty": "FSRS difficulty (1-10, higher = harder for you)",
                "stability": "FSRS stability in days — how long the memory is expected to hold",
                "interval": "Days until next review",
                "reps": "Number of successful reviews (0 = new card)",
                "lapseCount": "Number of times the card was forgotten",
                "leechFlag": "True if the card is a leech (repeatedly forgotten)"
              }
            },
            "cards.csv": {
              "description": "Same data as cards.json in CSV format for spreadsheet analysis"
            },
            "reviews.json": {
              "description": "Full review history — one entry per graded review across all cards",
              "fields": {
                "id": "UUID — unique review log identifier",
                "cardId": "UUID of the reviewed card (null if the card was deleted)",
                "cardType": "Card category at review time: kanji, vocabulary, grammar, listening",
                "timestamp": "ISO8601 date when the review occurred",
                "grade": "FSRS grade 1-4 (1=again, 2=hard, 3=good, 4=easy) — see grade_semantics below for what each value means pedagogically",
                "gradeLabel": "Human-readable grade: again, hard, good, easy",
                "responseTimeMs": "Time taken to answer, in milliseconds",
                "answeredValue": "The value the learner actually chose or produced, for any exercise format that offers a choice. Null for a self-graded flashcard — there is nothing to record, the learner graded their own recall. Where present, this is what makes confusion pairs (see confusions.json) analyzable: e.g. the learner was shown シ and answered ツ. Script is NOT uniform across rows: for the kana quiz this is the kana character itself (シ), not the romaji option label, so it can be compared directly against a card's front; a few rows fall back to the raw romaji option string when the character couldn't be resolved. A consumer must not assume one script.",
                "exerciseType": "Free-form identifier for the exercise format this grade came from. Null when not recorded. Two independent value spaces exist, distinguished by shape, not a shared enum: main-session values match ExerciseType.rawValue (e.g. kanjiStudy, vocabularyStudy, grammarStudy, listeningStudy); kana-drill values are 'kana.flashcard' or 'kana.quiz' (a surface that predates ExerciseType and grades kana cards outside the session pipeline).",
                "surface": "Where the review was graded from: iphone.session (main SRS session), iphone.drill (kana drill flashcard/quiz), or watch. 'watch' is reserved: no Watch code path persists a ReviewLog yet, so this export will never actually contain that value today — do not read its absence as evidence the learner isn't using the Watch."
              }
            },
            "confusions.json": {
              "description": "DERIVED aggregate, not a persisted table — computed from reviews.json at export time, every time. One row per distinct (expected, answered) pair with how many times it occurred in the exported window. This is the file with the highest diagnostic value: it names recurring confusions (e.g. シ/ツ, ソ/ン) instead of forcing an inference from accuracy alone.",
              "fields": {
                "expected": "The character/value the learner was shown (the reviewed card's front)",
                "answered": "The character/value the learner actually chose — see reviews.json.fields.answeredValue for the script caveat",
                "count": "Number of times this exact (expected, answered) pair occurred"
              },
              "exclusions": [
                "Rows where expected == answered are NOT included — a correct answer isn't a confusion. Per-item accuracy already lives in reviews.json/cards.json.",
                "Reviews with a null answeredValue are excluded (most flashcard/self-graded reviews today — only the kana quiz currently populates answeredValue, so confusions.json will be empty or kana-only until other formats adopt the same field).",
                "Reviews whose card was deleted (cardId present but no longer resolvable, or cardId null) are excluded — 'expected' cannot be determined without the card."
              ]
            },
            "outcomes.json": {
              "description": "Pool-based output drill outcomes (listening / shadowing) with no backing flashcard",
              "fields": {
                "id": "UUID — unique outcome entry identifier",
                "timestamp": "ISO8601 date when the drill was completed",
                "skill": "Skill measured: listening or speaking",
                "accuracy": "Accuracy 0.0-1.0 (binary pass/fail for listening, banded for shadowing)"
              }
            },
            "rpg.json": {
              "description": "RPG progression state",
              "fields": {
                "xp": "Total experience points earned",
                "level": "Current RPG level",
                "totalReviewsCompleted": "Lifetime review count",
                "totalSessionsCompleted": "Lifetime session count",
                "attributes": "Array of skill attributes with values (0-100 scale)",
                "inventoryCount": "Number of loot items collected",
                "unopenedLootBoxes": "Number of lootboxes waiting to be opened"
              }
            }
          },
          "grade_semantics": {
            "description": "What the 4 grade buttons mean, pedagogically — read this before computing any recall/retention rate from reviews.json or outcomes.json.",
            "1": {
              "label": "again",
              "meaning": "The learner failed to recall. This is the ONLY grade that counts as a lapse/failure — it resets the card's FSRS interval and is what leech detection counts."
            },
            "2": {
              "label": "hard",
              "meaning": "The learner recalled correctly, but slowly or with effort. This is a SUCCESS, not a failure, in the SRS sense — 'slow but correct'. A recall/retention rate must count hard as a success alongside good and easy; counting it as a failure understates the learner's actual retention and was a bug the app itself has fixed (recall-rate calculations now treat everything except again as success)."
            },
            "3": {
              "label": "good",
              "meaning": "Recalled correctly at the expected effort — the baseline success."
            },
            "4": {
              "label": "easy",
              "meaning": "Recalled correctly with no effort — success, and schedules a longer interval than good."
            },
            "recall_rate_formula": "successes / total, where successes = count(grade != again) = count(grade in {hard, good, easy})"
          },
          "usage_notes": [
            "All dates are ISO8601 format in UTC",
            "Card types: kanji, vocabulary, grammar, listening",
            "Ease factor follows FSRS algorithm conventions",
            "Leech detection threshold: 4 lapses",
            "See grade_semantics for what each of the 4 review grades means before computing any success/retention rate — grade 2 (hard) is a success, not a failure"
          ]
        }
        """
        // swiftlint:enable line_length
    }
}

// MARK: - Export Types

private struct CardExportRow: Codable, Sendable {
    let id: UUID
    let front: String
    let back: String
    let type: String
    let dueDate: Date
    let difficulty: Double
    let stability: Double
    let interval: Int
    let reps: Int
    let lapseCount: Int
    let leechFlag: Bool

    init(from dto: CardDTO) {
        self.id = dto.id
        self.front = dto.front
        self.back = dto.back
        self.type = dto.type.rawValue
        self.dueDate = dto.dueDate
        self.difficulty = dto.fsrsState.difficulty
        self.stability = dto.fsrsState.stability
        self.interval = dto.interval
        self.reps = dto.fsrsState.reps
        self.lapseCount = dto.lapseCount
        self.leechFlag = dto.leechFlag
    }
}

private struct ReviewExportRow: Codable, Sendable {
    let id: UUID
    let cardId: UUID?
    let cardType: String?
    let timestamp: Date
    let grade: Int
    let gradeLabel: String
    let responseTimeMs: Int
    /// See `ReviewLog.answeredValue` — nil for a self-graded flashcard,
    /// otherwise the value the learner chose/produced (script not uniform:
    /// kana character for the kana quiz, romaji as a fallback — a consumer
    /// must not assume one).
    let answeredValue: String?
    /// See `ReviewLog.exerciseType` — free-form, value space differs by
    /// prefix (see `context.json`'s `reviews.json.fields.exerciseType`).
    let exerciseType: String?
    /// See `ReviewLog.surface` — `"iphone.session"`, `"iphone.drill"`, or the
    /// reserved (not yet emitted) `"watch"`.
    let surface: String?

    init(from dto: ReviewLogDTO) {
        self.id = dto.id
        self.cardId = dto.cardId
        self.cardType = dto.cardType?.rawValue
        self.timestamp = dto.timestamp
        self.grade = dto.grade.rawValue
        self.gradeLabel = Self.label(for: dto.grade)
        self.responseTimeMs = dto.responseTimeMs
        self.answeredValue = dto.answeredValue
        self.exerciseType = dto.exerciseType
        self.surface = dto.surface
    }

    /// Explicit grade → label mapping for the exported `gradeLabel` field.
    /// An explicit switch (rather than `String(describing:)`) keeps the exported
    /// contract stable even if `Grade` later gains a `CustomStringConvertible`
    /// conformance for UI display, and is exhaustive-checked by the compiler.
    private static func label(for grade: Grade) -> String {
        switch grade {
        case .again: "again"
        case .hard: "hard"
        case .good: "good"
        case .easy: "easy"
        }
    }
}

/// Key for aggregating confusion pair counts in `generateConfusions`. Not
/// exported directly — `ConfusionExportRow` is the flattened, encodable shape.
private struct ConfusionPairKey: Hashable {
    let expected: String
    let answered: String
}

/// One row of `confusions.json`: an `(expected, answered)` character pair and
/// how many times it occurred across the exported review history. Derived at
/// export time by `generateConfusions` — nothing new persisted.
private struct ConfusionExportRow: Codable, Sendable {
    let expected: String
    let answered: String
    let count: Int
}

private struct OutcomeExportRow: Codable, Sendable {
    let id: UUID
    let timestamp: Date
    let skill: String
    let accuracy: Double

    init(from dto: ExerciseOutcomeLogDTO) {
        self.id = dto.id
        self.timestamp = dto.timestamp
        self.skill = dto.skill.rawValue
        self.accuracy = dto.accuracy
    }
}

/// Sendable so it can cross from the MainActor extraction step (in
/// `buildExportDirectory`) into the off-main `writeExportFiles` task.
private struct RPGExport: Codable, Sendable {
    let xp: Int
    let level: Int
    let totalReviewsCompleted: Int
    let totalSessionsCompleted: Int
    let attributes: [RPGAttribute]
    let inventoryCount: Int
    let unopenedLootBoxes: Int
}

// MARK: - Errors

/// Errors surfaced by the data export pipeline. Conforms to `LocalizedError`
/// so the UI can present a human-readable reason via `localizedDescription`.
enum ExportError: LocalizedError {
    case archivingFailed

    var errorDescription: String? {
        switch self {
        case .archivingFailed:
            return String(localized: "Could not create the export archive.")
        }
    }
}
