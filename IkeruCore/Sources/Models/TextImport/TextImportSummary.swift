import Foundation

// MARK: - TextImportSummary

/// What a month of reading adds up to — the figures behind « ce mois-ci tu as
/// lu 4 textes, 620 mots, couverture moyenne 81 % ».
///
/// A pure value computed from imports, so the arithmetic that a learner will
/// read as a statement about themselves can be tested rather than eyeballed.
public struct TextImportSummary: Sendable, Equatable {

    /// Texts imported in the window.
    public let textCount: Int

    /// Words kept from them, across all texts.
    public let wordCount: Int

    /// Mean coverage over the texts that HAVE one, 0…1 — `nil` when none does.
    ///
    /// Texts without a measurable coverage are excluded from the mean rather
    /// than counted as zero. A photo the OCR could not read is not a text the
    /// learner understood 0 % of; folding it in as a zero would quietly tell
    /// them they are getting worse.
    public let averageCoverage: Double?

    public init(textCount: Int, wordCount: Int, averageCoverage: Double?) {
        self.textCount = textCount
        self.wordCount = wordCount
        self.averageCoverage = averageCoverage
    }

    /// Nothing read in the window — the view shows no summary at all rather
    /// than three zeros.
    public var isEmpty: Bool { textCount == 0 }

    /// Summarises the imports created on or after `since`.
    ///
    /// - Parameters:
    ///   - imports: every live import, in any order.
    ///   - since: the start of the window. Defaults to the beginning of time,
    ///     which summarises everything.
    public static func make(from imports: [TextImportDTO],
                            since: Date = .distantPast) -> TextImportSummary {
        let window = imports.filter { $0.createdAt >= since }
        let coverages = window.compactMap(\.coverage)
        return TextImportSummary(
            textCount: window.count,
            wordCount: window.reduce(0) { $0 + $1.wordCount },
            averageCoverage: coverages.isEmpty
                ? nil
                : coverages.reduce(0, +) / Double(coverages.count)
        )
    }

    /// The start of the current calendar month, in the learner's calendar.
    public static func startOfMonth(containing date: Date,
                                    calendar: Calendar = .current) -> Date {
        calendar.date(from: calendar.dateComponents([.year, .month], from: date)) ?? date
    }
}
