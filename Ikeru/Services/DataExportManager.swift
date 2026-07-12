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

        let zipURL = try zipDirectory(exportDir)
        Logger.ui.info("Data export archived at \(zipURL.path)")
        return zipURL
    }

    /// Writes every export file into a fresh temporary directory and returns it.
    /// Factored out of `exportData` so the file contents can be validated
    /// independently of the archiving step.
    func buildExportDirectory(modelContainer: ModelContainer) async throws -> URL {
        let exportDir = FileManager.default.temporaryDirectory
            .appending(path: "ikeru-export-\(Date().timeIntervalSince1970)", directoryHint: .isDirectory)

        try FileManager.default.createDirectory(at: exportDir, withIntermediateDirectories: true)

        let context = modelContainer.mainContext
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        // Cards
        let cardRepo = CardRepository(modelContainer: modelContainer)
        let allCards = await cardRepo.allCards()
        let cardsData = try encoder.encode(allCards.map { CardExportRow(from: $0) })
        try cardsData.write(to: exportDir.appending(path: "cards.json"))

        // Cards CSV
        let csv = generateCardsCSV(cards: allCards)
        try csv.write(to: exportDir.appending(path: "cards.csv"), atomically: true, encoding: .utf8)

        // Review logs — every recorded grade across all cards. Empty history
        // still writes a valid `[]` rather than omitting the promised file.
        let reviewLogs = await cardRepo.allReviewLogs(from: .distantPast, to: .distantFuture)
        let reviewsData = try encoder.encode(reviewLogs.map { ReviewExportRow(from: $0) })
        try reviewsData.write(to: exportDir.appending(path: "reviews.json"))

        // RPG State
        let rpgStates = (try? context.fetch(FetchDescriptor<RPGState>())) ?? []
        if let rpg = rpgStates.first {
            let rpgExport = RPGExport(
                xp: rpg.xp,
                level: rpg.level,
                totalReviewsCompleted: rpg.totalReviewsCompleted,
                totalSessionsCompleted: rpg.totalSessionsCompleted,
                attributes: rpg.attributes,
                inventoryCount: rpg.lootInventory.count,
                unopenedLootBoxes: rpg.unopenedLootBoxes.count
            )
            try encoder.encode(rpgExport).write(to: exportDir.appending(path: "rpg.json"))
        }

        // Context file (data model documentation)
        let contextJSON = generateContextJSON()
        try contextJSON.write(
            to: exportDir.appending(path: "context.json"),
            atomically: true,
            encoding: .utf8
        )

        Logger.ui.info("Data export written to \(exportDir.path)")
        return exportDir
    }

    // MARK: - Archiving

    /// Zips a directory into a sibling `.zip` file using `NSFileCoordinator`'s
    /// `.forUploading` reading intent — the system-provided, dependency-free way
    /// to produce a zip of a folder. The coordinator hands back a temporary
    /// archive that is only valid inside the accessor closure, so it is moved to
    /// a stable location before returning.
    func zipDirectory(_ directory: URL) throws -> URL {
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

        if let coordinatorError { throw coordinatorError }
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

    private func generateCardsCSV(cards: [CardDTO]) -> String {
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

    private func escapeCSV(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") {
            return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return value
    }

    // MARK: - Context JSON

    private func generateContextJSON() -> String {
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

private struct CardExportRow: Codable {
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

private struct ReviewExportRow: Codable {
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
        self.gradeLabel = String(describing: dto.grade)
        self.responseTimeMs = dto.responseTimeMs
    }
}

private struct RPGExport: Codable {
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
