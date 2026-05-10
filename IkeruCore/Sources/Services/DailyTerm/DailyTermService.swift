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
    private let catalogByWord: [String: DailyTermCandidate]
    private let calendar: Calendar
    private let locale: Locale

    public init(
        repository: DailyTermRepository,
        catalog: [DailyTermCandidate] = DailyTermCatalog.all,
        calendar: Calendar = .current,
        locale: Locale = .current
    ) {
        self.repository = repository
        self.catalog = catalog
        self.catalogByWord = Dictionary(uniqueKeysWithValues: catalog.map { ($0.word, $0) })
        self.calendar = calendar
        self.locale = locale
    }

    /// Re-derives meaning + caption from the catalog at the service's
    /// current locale, ignoring whatever was persisted on the DailyTerm
    /// row at creation time. This is what makes the feature "switch
    /// language" — existing rows pick up FR text the moment the app
    /// runs in French.
    private func localized(_ dto: DailyTermDTO) -> DailyTermDTO {
        guard let candidate = catalogByWord[dto.word] else { return dto }
        let meaning = candidate.localizedMeaning(for: locale)
        let caption = composeCaption(for: candidate, on: dto.date)
        return DailyTermDTO(
            id: dto.id,
            date: dto.date,
            word: dto.word,
            reading: dto.reading,
            pronunciation: dto.pronunciation,
            meaning: meaning,
            caption: caption,
            jlptLevel: dto.jlptLevel,
            revealedAt: dto.revealedAt,
            addedToDictionary: dto.addedToDictionary,
            createdAt: dto.createdAt
        )
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
            return localized(existing)
        }

        let usedWords = await repository.usedWords()
            .union(existingDictionaryWords)

        let candidate = pickCandidate(for: normalised, excluding: usedWords)
        // Persist the English text as a safety net (back-compat with rows
        // that may be read by a future build without locale awareness).
        // Reads always re-derive via `localized(_:)` so the persisted
        // string is treated as dead-but-present.
        let caption = composeCaption(for: candidate, on: normalised, locale: Locale(identifier: "en"))

        let stored = await repository.upsertTerm(
            on: normalised,
            word: candidate.word,
            reading: candidate.reading,
            pronunciation: candidate.pronunciation,
            meaning: candidate.meaning,
            caption: caption,
            jlptLevel: candidate.jlptLevel
        )
        return localized(stored)
    }

    /// Term scheduled for the day immediately preceding `day`, if one exists.
    /// Used for the "discreet reminder of yesterday's term".
    public func previousDayTerm(before day: Date = Date()) async -> DailyTermDTO? {
        let normalised = calendar.startOfDay(for: day)
        let recent = await repository.termsBefore(normalised, limit: 1)
        return recent.first.map(localized)
    }

    /// Past terms (most-recent first), capped at `limit`.
    public func recentTerms(before day: Date = Date(), limit: Int = 30) async -> [DailyTermDTO] {
        let normalised = calendar.startOfDay(for: day)
        return await repository.termsBefore(normalised, limit: limit).map(localized)
    }

    /// Past terms the user never opened — surfaced in the "missed terms" list.
    public func missedTerms(before day: Date = Date(), limit: Int = 30) async -> [DailyTermDTO] {
        let normalised = calendar.startOfDay(for: day)
        let recent = await repository.termsBefore(normalised, limit: limit)
        return recent.filter { $0.revealedAt == nil }.map(localized)
    }

    public func markRevealed(termId: UUID) async {
        await repository.markRevealed(termId: termId)
    }

    public func markAddedToDictionary(termId: UUID) async {
        await repository.markAddedToDictionary(termId: termId)
    }

    // MARK: - Selection

    /// Pure selection function — exposed for tests.
    ///
    /// Algorithm:
    /// 1. Drop catalog entries already present in `usedWords`.
    /// 2. If the working pool is empty (every catalog word has been used),
    ///    fall back to the full catalog and use the date seed both for
    ///    scoring and as the modulo index, so consecutive days continue
    ///    to vary instead of locking on a single word.
    /// 3. Score each candidate by the number of overlapping tags with the
    ///    day's tags (season/weekday/month). Pick from the top-scoring
    ///    bucket, tiebroken by `dateSeed`.
    public func pickCandidate(
        for day: Date,
        excluding usedWords: Set<String>
    ) -> DailyTermCandidate {
        let dayTags = Self.tags(for: day, calendar: calendar)
        let seed = Self.dateSeed(for: day, calendar: calendar)

        let pool = catalog.filter { !usedWords.contains($0.word) }
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

        // Stable order so the seed → index mapping is deterministic
        // regardless of the catalog literal order.
        let ordered = topCandidates.sorted { $0.word < $1.word }
        let index = Int(seed % UInt64(max(ordered.count, 1)))
        return ordered[index]
    }

    /// Composes a date-aware caption for the term. Rotates among a few
    /// wrapping templates so the daily prompt doesn't read identically
    /// every day. Locale-aware so the FR app sees French phrasing.
    public func composeCaption(
        for candidate: DailyTermCandidate,
        on day: Date
    ) -> String {
        composeCaption(for: candidate, on: day, locale: locale)
    }

    /// Locale-overridable variant — useful for tests and for persisting
    /// a back-compat English caption alongside FR rendering.
    public func composeCaption(
        for candidate: DailyTermCandidate,
        on day: Date,
        locale: Locale
    ) -> String {
        let isFR = locale.language.languageCode?.identifier == "fr"
        let flavour = candidate.localizedFlavour(for: locale)

        let weekdayPhrase = isFR
            ? Self.weekdayPhraseFR(for: day, calendar: calendar)
            : Self.weekdayPhrase(for: day, calendar: calendar)
        let seasonPhrase = isFR
            ? Self.seasonPhraseFR(for: day, calendar: calendar)
            : Self.seasonPhrase(for: day, calendar: calendar)
        let dayPhrase = "\(weekdayPhrase) \(seasonPhrase)".trimmingCharacters(in: .whitespaces)

        if dayPhrase.isEmpty {
            return flavour
        }

        // Pick a template deterministically — same day → same caption,
        // different days alternate phrasings to avoid sounding formulaic.
        let templatesEN: [(String, String) -> String] = [
            { phrase, flavour in "On this \(phrase): \(flavour)." },
            { phrase, flavour in "For your \(phrase): \(flavour)." },
            { phrase, flavour in "A word for a \(phrase) — \(flavour)." },
            { phrase, flavour in "\(flavour). Suited to a \(phrase)." }
        ]
        let templatesFR: [(String, String) -> String] = [
            { phrase, flavour in "En ce \(phrase) : \(flavour)." },
            { phrase, flavour in "Pour ton \(phrase) : \(flavour)." },
            { phrase, flavour in "Un mot pour un \(phrase) — \(flavour)." },
            { phrase, flavour in "\(flavour). Pour un \(phrase)." }
        ]
        let templates = isFR ? templatesFR : templatesEN
        let seed = Self.dateSeed(for: day, calendar: calendar)
        let template = templates[Int(seed % UInt64(templates.count))]
        return template(dayPhrase, flavour)
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

    /// French equivalents — masculine forms so they combine cleanly with
    /// season adjectives. Used when the service's locale is `fr`.
    static func weekdayPhraseFR(for day: Date, calendar: Calendar) -> String {
        let weekday = calendar.component(.weekday, from: day)
        switch weekday {
        case 1: return "dimanche tranquille"
        case 2: return "lundi de reprise"
        case 3: return "mardi"
        case 4: return "mercredi de mi-semaine"
        case 5: return "jeudi"
        case 6: return "vendredi qui approche"
        case 7: return "samedi paisible"
        default: return ""
        }
    }

    static func seasonPhraseFR(for day: Date, calendar: Calendar) -> String {
        let month = calendar.component(.month, from: day)
        switch month {
        case 3, 4, 5: return "printanier"
        case 6, 7, 8: return "estival"
        case 9, 10, 11: return "automnal"
        case 12, 1, 2: return "hivernal"
        default: return ""
        }
    }
}
