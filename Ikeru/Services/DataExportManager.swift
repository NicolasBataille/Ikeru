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
    /// rpg.json, context.json, cards.csv.
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
            rpgExport = RPGExport(
                xp: rpg.xp,
                level: rpg.level,
                totalReviewsCompleted: rpg.totalReviewsCompleted,
                totalSessionsCompleted: rpg.totalSessionsCompleted,
                attributes: rpg.attributes,
                inventoryCount: rpg.lootInventory.count,
                unopenedLootBoxes: rpg.unopenedLootBoxes.count
            )
        }

        // Only Sendable value types (CardDTO, ReviewLogDTO, RPGExport) cross
        // into the detached task below — no ModelContext, ModelContainer, or
        // @Model instance is ever captured off the main actor.
        let exportDir = try await Task.detached(priority: .utility) {
            try Self.writeExportFiles(cards: allCards, reviews: reviewLogs, rpg: rpgExport)
        }.value

        Logger.ui.info("Data export written to \(exportDir.path)")
        return exportDir
    }

    // MARK: - Off-main writing

    /// Builds a fresh temporary directory and writes every export file into
    /// it: cards.json, cards.csv, reviews.json, rpg.json (if present), and
    /// context.json. Runs off the main actor — only Sendable inputs
    /// (`CardDTO`, `ReviewLogDTO`, `RPGExport`) are accepted.
    nonisolated private static func writeExportFiles(
        cards: [CardDTO],
        reviews: [ReviewLogDTO],
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
        var csv = "id,front,back,type,due_date,ease_factor,interval,reps,lapse_count,leech_flag\n"
        let dateFormatter = ISO8601DateFormatter()

        for card in cards {
            let row = [
                card.id.uuidString,
                escapeCSV(card.front),
                escapeCSV(card.back),
                card.type.rawValue,
                dateFormatter.string(from: card.dueDate),
                String(format: "%.4f", card.easeFactor),
                "\(card.interval)",
                "\(card.fsrsState.reps)",
                "\(card.lapseCount)",
                "\(card.leechFlag)",
            ]
            csv += row.joined(separator: ",") + "\n"
        }
        return csv
    }

    nonisolated private static func escapeCSV(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") {
            return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return value
    }

    // MARK: - Context JSON

    nonisolated private static func generateContextJSON() -> String {
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
                "easeFactor": "FSRS ease factor (higher = easier, typically 1.3-3.0)",
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
                "grade": "FSRS grade 1-4 (1=again, 2=hard, 3=good, 4=easy)",
                "gradeLabel": "Human-readable grade: again, hard, good, easy",
                "responseTimeMs": "Time taken to answer, in milliseconds"
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
          "usage_notes": [
            "All dates are ISO8601 format in UTC",
            "Card types: kanji, vocabulary, grammar, listening",
            "Ease factor follows FSRS algorithm conventions",
            "Leech detection threshold: 4 lapses"
          ]
        }
        """
    }
}

// MARK: - Export Types

private struct CardExportRow: Codable, Sendable {
    let id: UUID
    let front: String
    let back: String
    let type: String
    let dueDate: Date
    let easeFactor: Double
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
        self.easeFactor = dto.easeFactor
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

    init(from dto: ReviewLogDTO) {
        self.id = dto.id
        self.cardId = dto.cardId
        self.cardType = dto.cardType?.rawValue
        self.timestamp = dto.timestamp
        self.grade = dto.grade.rawValue
        self.gradeLabel = Self.label(for: dto.grade)
        self.responseTimeMs = dto.responseTimeMs
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
