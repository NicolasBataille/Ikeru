import Foundation
import SwiftData
import IkeruCore
import os

// MARK: - DataExportManager

/// Exports learning data in JSON and CSV formats for AI agent analysis.
/// Generates a structured export bundle with a context.json describing the data model.
@MainActor
final class DataExportManager {

    // MARK: - Export

    /// Generates a complete data export bundle as a temporary directory URL.
    /// Contains: cards.json, reviews.json, rpg.json, context.json, cards.csv
    func exportData(modelContainer: ModelContainer) async throws -> URL {
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

        Logger.ui.info("Data export completed at \(exportDir.path)")
        return exportDir
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

private struct RPGExport: Codable {
    let xp: Int
    let level: Int
    let totalReviewsCompleted: Int
    let totalSessionsCompleted: Int
    let attributes: [RPGAttribute]
    let inventoryCount: Int
    let unopenedLootBoxes: Int
}
