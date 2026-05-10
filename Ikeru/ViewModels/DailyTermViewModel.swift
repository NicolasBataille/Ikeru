import SwiftUI
import SwiftData
import IkeruCore
import os

// MARK: - DailyTermViewModel

/// View model coordinating the daily term feature on the Home screen.
///
/// Owns the state surfaced to the UI:
/// - `today`: the term scheduled for the current day, generated lazily.
/// - `yesterday`: yesterday's term (if any), used for the discreet reminder.
/// - `recent`: a recent history of past terms (most-recent first), both
///   seen and missed. The view distinguishes them visually via
///   `revealedAt`.
/// - `missed`: convenience accessor — terms in `recent` with no
///   `revealedAt` set.
@MainActor
@Observable
public final class DailyTermViewModel {

    // MARK: - Exposed State

    public private(set) var today: DailyTermDTO?
    public private(set) var yesterday: DailyTermDTO?
    public private(set) var recent: [DailyTermDTO] = []
    public private(set) var hasLoaded: Bool = false

    /// Past terms with no `revealedAt` — convenience for callers that
    /// only want missed days.
    public var missed: [DailyTermDTO] {
        recent.filter { $0.revealedAt == nil }
    }

    /// Whether today's term has not yet been opened by the user — drives the banner.
    public var todayNeedsReveal: Bool {
        guard let today else { return false }
        return today.revealedAt == nil
    }

    /// Whether the daily-term feature is enabled in user settings.
    public var isFeatureEnabled: Bool {
        UserDefaults.standard.bool(forKey: DailyTermSettings.enabledKey)
    }

    // MARK: - Dependencies

    private let service: DailyTermService
    private let dailyTermRepository: DailyTermRepository
    private let vocabularyRepository: VocabularyRepository

    /// Calendar day represented by the currently-loaded `today`. Used to
    /// detect when a midnight rollover should re-load.
    private var currentDay: Date?

    // MARK: - Init

    public init(modelContainer: ModelContainer) {
        let dailyTermRepo = DailyTermRepository(modelContainer: modelContainer)
        let vocabRepo = VocabularyRepository(modelContainer: modelContainer)
        self.dailyTermRepository = dailyTermRepo
        self.vocabularyRepository = vocabRepo
        self.service = DailyTermService(repository: dailyTermRepo)
    }

    // MARK: - Loading

    /// Loads (and lazily generates) the term for today, plus yesterday
    /// and the recent history. Cheap to call from `onAppear`.
    public func load(now: Date = Date()) async {
        guard isFeatureEnabled else {
            today = nil
            yesterday = nil
            recent = []
            currentDay = nil
            hasLoaded = true
            return
        }

        let dictionaryWords = Set((await vocabularyRepository.allEntries()).map(\.word))
        let todayDTO = await service.termForDay(now, existingDictionaryWords: dictionaryWords)
        today = todayDTO
        currentDay = Calendar.current.startOfDay(for: now)

        yesterday = await service.previousDayTerm(before: now)
        recent = await service.recentTerms(before: now, limit: 30)

        hasLoaded = true
        Logger.dailyTerm.debug(
            "Daily term loaded: today=\(todayDTO.word, privacy: .public) revealed=\(todayDTO.revealedAt != nil)"
        )
    }

    /// Re-loads only if the calendar day has changed since the last load.
    /// Used by the home view to handle midnight rollover and time-zone
    /// changes without a full re-fetch on every `onAppear`.
    public func reloadIfDayChanged(now: Date = Date()) async {
        let day = Calendar.current.startOfDay(for: now)
        if currentDay != day {
            await load(now: now)
        }
    }

    // MARK: - Mutations

    /// Marks today's term (or any past term) as opened — drives the
    /// "missed" → "revealed" transition in the history.
    /// - Returns: an updated DTO snapshot if a change was made, otherwise nil.
    @discardableResult
    public func markRevealed(_ term: DailyTermDTO, now: Date = Date()) async -> DailyTermDTO? {
        guard term.revealedAt == nil else { return nil }
        await service.markRevealed(termId: term.id)
        let updated = DailyTermDTO(
            id: term.id,
            date: term.date,
            word: term.word,
            reading: term.reading,
            pronunciation: term.pronunciation,
            meaning: term.meaning,
            caption: term.caption,
            jlptLevel: term.jlptLevel,
            revealedAt: now,
            addedToDictionary: term.addedToDictionary,
            createdAt: term.createdAt
        )
        if term.id == today?.id {
            today = updated
        }
        recent = await service.recentTerms(before: now, limit: 30)
        return updated
    }

    /// Adds the term to the user's personal dictionary and stores the
    /// link on the daily term row.
    /// - Returns: an updated DTO snapshot if the write succeeded, otherwise nil.
    @discardableResult
    public func addToDictionary(_ term: DailyTermDTO, now: Date = Date()) async -> DailyTermDTO? {
        guard !term.addedToDictionary else { return nil }
        _ = await vocabularyRepository.addEntry(
            word: term.word,
            reading: term.reading,
            meaning: term.meaning,
            jlptLevel: term.jlptLevel
        )
        await service.markAddedToDictionary(termId: term.id)

        let updated = DailyTermDTO(
            id: term.id,
            date: term.date,
            word: term.word,
            reading: term.reading,
            pronunciation: term.pronunciation,
            meaning: term.meaning,
            caption: term.caption,
            jlptLevel: term.jlptLevel,
            revealedAt: term.revealedAt,
            addedToDictionary: true,
            createdAt: term.createdAt
        )
        if term.id == today?.id {
            today = updated
        }
        recent = await service.recentTerms(before: now, limit: 30)
        Logger.dailyTerm.info("Daily term added to dictionary: \(term.word, privacy: .public)")
        return updated
    }
}

// MARK: - Settings keys

/// Centralised UserDefaults keys for the daily-term feature.
public enum DailyTermSettings {
    /// Whether the daily-term feature is enabled.
    public static let enabledKey = "ikeru.dailyterm.enabled"
    /// Hour-of-day (0-23) at which to fire the daily-term notification.
    public static let hourKey = "ikeru.dailyterm.hour"
    /// Minute-of-hour (0-59) for the daily-term notification.
    public static let minuteKey = "ikeru.dailyterm.minute"

    public static let defaultHour = 9
    public static let defaultMinute = 0
}

// MARK: - Notification names

extension Notification.Name {
    /// Posted when the user taps the daily-term local notification.
    /// `HomeView` listens for this to present the reveal sheet.
    public static let openDailyTerm = Notification.Name("ikeru.dailyterm.open")
}
