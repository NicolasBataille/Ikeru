import Foundation
import os

// MARK: - DailyTermService

/// Picks the term of the day, persists it, and helps surface yesterday's
/// term plus the missed-terms history.
///
/// Selection algorithm (deterministic per day):
///
/// 1. Pull every catalog candidate.
/// 2. Drop anything already used on a previous day (`usedWords`).
/// 3. Drop anything the user has already added to their personal dictionary
///    (`existingDictionaryWords`).
/// 4. Score the remaining candidates against the day's tags
///    (season, weekday, time of year). Higher score = better match.
/// 5. Tiebreak with a deterministic hash seeded by the date so the same
///    day always produces the same word for the same user.
///
/// If nothing survives the filters (very unlikely with the built-in catalog
/// of ~50 entries), fall back to the seasonal pool, then to the full
/// catalog. This guarantees a term every day.
public struct DailyTermService: Sendable {

    private let repository: DailyTermRepository
    private let catalog: [DailyTermCandidate]
    private let calendar: Calendar

    public init(
        repository: DailyTermRepository,
        catalog: [DailyTermCandidate] = DailyTermCatalog.all,
        calendar: Calendar = .current
    ) {
        self.repository = repository
        self.catalog = catalog
        self.calendar = calendar
    }

    // MARK: - Public API

    /// Returns the term for the given day, generating and persisting it
    /// on first call. Repeats are avoided across past days and against
    /// the supplied dictionary words.
    @discardableResult
    public func termForDay(
        _ day: Date = Date(),
        existingDictionaryWords: Set<String> = []
    ) async -> DailyTermDTO {
        let normalised = calendar.startOfDay(for: day)

        if let existing = await repository.term(on: normalised) {
            return existing
        }

        let usedWords = await repository.usedWords()
            .union(existingDictionaryWords)

        let candidate = pickCandidate(for: normalised, excluding: usedWords)
        let caption = composeCaption(for: candidate, on: normalised)

        return await repository.upsertTerm(
            on: normalised,
            word: candidate.word,
            reading: candidate.reading,
            pronunciation: candidate.pronunciation,
            meaning: candidate.meaning,
            caption: caption,
            jlptLevel: candidate.jlptLevel
        )
    }

    /// Term scheduled for the day immediately preceding `day`, if one exists.
    /// Used for the "discreet reminder of yesterday's term".
    public func previousDayTerm(before day: Date = Date()) async -> DailyTermDTO? {
        let recent = await repository.termsBefore(day, limit: 1)
        return recent.first
    }

    /// Past terms (most-recent first), capped at `limit`.
    public func recentTerms(before day: Date = Date(), limit: Int = 30) async -> [DailyTermDTO] {
        await repository.termsBefore(day, limit: limit)
    }

    /// Past terms the user never opened — surfaced in the "missed terms" list.
    public func missedTerms(before day: Date = Date(), limit: Int = 30) async -> [DailyTermDTO] {
        let recent = await repository.termsBefore(day, limit: limit)
        return recent.filter { $0.revealedAt == nil }
    }

    public func markRevealed(termId: UUID) async {
        await repository.markRevealed(termId: termId)
    }

    public func markAddedToDictionary(termId: UUID) async {
        await repository.markAddedToDictionary(termId: termId)
    }

    // MARK: - Selection

    /// Pure selection function — exposed for tests.
    public func pickCandidate(
        for day: Date,
        excluding usedWords: Set<String>
    ) -> DailyTermCandidate {
        let dayTags = Self.tags(for: day, calendar: calendar)
        let seed = Self.dateSeed(for: day, calendar: calendar)

        let pool = catalog.filter { !usedWords.contains($0.word) }

        // No candidates left — restart the rotation but keep the date-aware
        // tiebreak, scoring against the full catalog.
        let workingPool = pool.isEmpty ? catalog : pool

        let scored: [(candidate: DailyTermCandidate, score: Int)] = workingPool.map { candidate in
            let overlap = candidate.tags.reduce(0) { acc, tag in
                acc + (dayTags.contains(tag) ? 1 : 0)
            }
            return (candidate, overlap)
        }

        let bestScore = scored.map(\.score).max() ?? 0
        let topCandidates: [DailyTermCandidate]
        if bestScore > 0 {
            topCandidates = scored.filter { $0.score == bestScore }.map(\.candidate)
        } else {
            topCandidates = workingPool
        }

        let index = Int(seed % UInt64(max(topCandidates.count, 1)))
        return topCandidates[index]
    }

    /// Composes a date-aware caption for the term, in the spirit
    /// "today's term: [flavour], on a [season/weekday] morning…".
    public func composeCaption(
        for candidate: DailyTermCandidate,
        on day: Date
    ) -> String {
        let weekdayPhrase = Self.weekdayPhrase(for: day, calendar: calendar)
        let seasonPhrase = Self.seasonPhrase(for: day, calendar: calendar)
        let dayPhrase = "\(weekdayPhrase) \(seasonPhrase)".trimmingCharacters(in: .whitespaces)

        if dayPhrase.isEmpty {
            return candidate.flavour
        }
        return "On this \(dayPhrase): \(candidate.flavour)."
    }

    // MARK: - Date helpers

    /// Tags relevant to a particular day — season, weekday, month, time of week.
    static func tags(for day: Date, calendar: Calendar) -> Set<String> {
        var tags: Set<String> = ["any"]
        let components = calendar.dateComponents([.month, .weekday], from: day)

        if let month = components.month {
            switch month {
            case 3, 4, 5: tags.insert("spring")
            case 6, 7, 8: tags.insert("summer")
            case 9, 10, 11: tags.insert("autumn")
            case 12, 1, 2: tags.insert("winter")
            default: break
            }
            let monthNames = [
                "january", "february", "march", "april", "may", "june",
                "july", "august", "september", "october", "november", "december"
            ]
            if (1...12).contains(month) {
                tags.insert(monthNames[month - 1])
            }
        }

        if let weekday = components.weekday {
            // Calendar uses 1 = Sunday … 7 = Saturday in en-US; remap.
            let weekdayNames = [
                "sunday", "monday", "tuesday", "wednesday",
                "thursday", "friday", "saturday"
            ]
            let index = ((weekday - 1) % 7 + 7) % 7
            tags.insert(weekdayNames[index])
            if weekday == 1 || weekday == 7 {
                tags.insert("weekend")
            }
        }
        return tags
    }

    /// Stable per-day seed used to pick deterministically among equally
    /// good candidates. Same day → same word.
    static func dateSeed(for day: Date, calendar: Calendar) -> UInt64 {
        let components = calendar.dateComponents([.year, .month, .day], from: day)
        let year = UInt64(components.year ?? 0)
        let month = UInt64(components.month ?? 0)
        let dayValue = UInt64(components.day ?? 0)
        // Mix the components — the constants are arbitrary primes.
        return year &* 100_003 &+ month &* 1_009 &+ dayValue &* 31
    }

    static func weekdayPhrase(for day: Date, calendar: Calendar) -> String {
        let weekday = calendar.component(.weekday, from: day)
        switch weekday {
        case 1: return "easy Sunday"
        case 2: return "fresh-start Monday"
        case 3: return "Tuesday"
        case 4: return "midweek Wednesday"
        case 5: return "Thursday"
        case 6: return "almost-Friday"
        case 7: return "slow Saturday"
        default: return ""
        }
    }

    static func seasonPhrase(for day: Date, calendar: Calendar) -> String {
        let month = calendar.component(.month, from: day)
        switch month {
        case 3, 4, 5: return "spring day"
        case 6, 7, 8: return "summer day"
        case 9, 10, 11: return "autumn day"
        case 12, 1, 2: return "winter day"
        default: return "day"
        }
    }
}
