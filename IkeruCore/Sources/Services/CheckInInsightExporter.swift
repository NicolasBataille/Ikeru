import Foundation
import os

/// Exports weekly check-in data as structured JSON for external AI agent analysis.
///
/// The exported file is placed in the app's Documents directory and uses a
/// timestamped filename for uniqueness. The JSON schema is versioned for
/// forward compatibility.
public final class CheckInInsightExporter: Sendable {

    // MARK: - Dependencies

    private let cardRepository: CardRepository
    /// FileManager.default is thread-safe but not Sendable.
    nonisolated(unsafe) private let fileManager: FileManager

    // MARK: - Init

    public init(
        cardRepository: CardRepository,
        fileManager: FileManager = .default
    ) {
        self.cardRepository = cardRepository
        self.fileManager = fileManager
    }

    // MARK: - Export

    /// Exports the weekly summary and associated data to a JSON file.
    ///
    /// - Parameters:
    ///   - summary: The weekly check-in summary to export.
    ///   - learnerFeedback: Feedback messages captured during the check-in conversation.
    /// - Returns: The file URL of the exported JSON.
    /// - Throws: If the file cannot be written.
    public func exportInsights(
        summary: WeeklyCheckInSummary,
        learnerFeedback: [String] = []
    ) async throws -> URL {
        let reviewLogs = await cardRepository.allReviewLogs(
            from: summary.weekStartDate,
            to: summary.weekEndDate
        )
        let skillAccuracies = computeSkillAccuracies(from: reviewLogs)

        let envelope = CheckInExportEnvelope(
            summary: summary,
            skillAccuracies: skillAccuracies,
            learnerFeedback: learnerFeedback
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        let data = try encoder.encode(envelope)
        let fileURL = try exportFileURL(for: summary.weekEndDate)
        try data.write(to: fileURL, options: .atomic)

        Logger.ai.info("Exported check-in insights to \(fileURL.lastPathComponent)")
        return fileURL
    }

    // MARK: - Private

    /// Builds the export file URL with a timestamped name.
    private func exportFileURL(for date: Date) throws -> URL {
        let documentsURL = try fileManager.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let dateString = formatter.string(from: date)

        let filename = "ikeru-checkin-\(dateString).json"
        return documentsURL.appendingPathComponent(filename)
    }

    /// Computes per-skill accuracy from review logs.
    private func computeSkillAccuracies(from logs: [ReviewLogDTO]) -> [String: Double] {
        var skillLogs: [String: [ReviewLogDTO]] = [:]
        for log in logs {
            let name = skillName(for: log.cardType)
            skillLogs[name, default: []].append(log)
        }

        var accuracies: [String: Double] = [:]
        for (skill, reviews) in skillLogs {
            let successes = reviews.filter { $0.grade == .good || $0.grade == .easy }.count
            accuracies[skill] = reviews.isEmpty ? 0 : Double(successes) / Double(reviews.count)
        }
        return accuracies
    }

    /// Maps CardType to a human-readable skill name.
    private func skillName(for cardType: CardType?) -> String {
        switch cardType {
        case .kanji, .vocabulary:
            "reading"
        case .grammar:
            "writing"
        case .listening:
            "listening"
        case nil:
            "unknown"
        }
    }
}
