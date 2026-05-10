import SwiftUI
import SwiftData
import IkeruCore
import os

// MARK: - DailyTermViewModel

/// View model coordinating the daily term feature on the Home screen.
///
/// Owns three pieces of state surfaced to the UI:
/// - `today`: the term scheduled for the current day, generated lazily.
/// - `yesterday`: yesterday's term (if any), used for the discreet reminder.
/// - `missed`: a recent history of past terms (most-recent first), with
///   `revealedAt == nil` items called out as missed.
@MainActor
@Observable
public final class DailyTermViewModel {

    // MARK: - Exposed State

    public private(set) var today: DailyTermDTO?
    public private(set) var yesterday: DailyTermDTO?
    public private(set) var missed: [DailyTermDTO] = []
    public private(set) var hasLoaded: Bool = false

    /// Whether the user added today's term to their dictionary during this session.
    public private(set) var addedToDictionaryThisSession: Bool = false

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

    // MARK: - Init

    public init(modelContainer: ModelContainer) {
        let dailyTermRepo = DailyTermRepository(modelContainer: modelContainer)
        let vocabRepo = VocabularyRepository(modelContainer: modelContainer)
        self.dailyTermRepository = dailyTermRepo
        self.vocabularyRepository = vocabRepo
        self.service = DailyTermService(repository: dailyTermRepo)
    }

    // MARK: - Loading

    /// Loads (and lazily generates) the term for today, plus yesterday and the
    /// missed-terms list. Cheap to call from `onAppear`.
    public func load(now: Date = Date()) async {
        guard isFeatureEnabled else {
            today = nil
            yesterday = nil
            missed = []
            hasLoaded = true
            return
        }

        let dictionaryWords = Set((await vocabularyRepository.allEntries()).map(\.word))
        let todayDTO = await service.termForDay(now, existingDictionaryWords: dictionaryWords)
        today = todayDTO
        addedToDictionaryThisSession = todayDTO.addedToDictionary

        yesterday = await service.previousDayTerm(before: now)
        missed = await service.missedTerms(before: now, limit: 14)

        hasLoaded = true
        Logger.dailyTerm.debug(
            "Daily term loaded: today=\(todayDTO.word, privacy: .public) revealed=\(todayDTO.revealedAt != nil)"
        )
    }

    // MARK: - Mutations

    /// Marks today's term (or any past term) as opened — drives the
    /// "missed" → "revealed" transition in the history.
    public func markRevealed(_ term: DailyTermDTO) async {
        guard term.revealedAt == nil else { return }
        await service.markRevealed(termId: term.id)
        if term.id == today?.id, let updated = today {
            today = DailyTermDTO(
                id: updated.id,
                date: updated.date,
                word: updated.word,
                reading: updated.reading,
                pronunciation: updated.pronunciation,
                meaning: updated.meaning,
                caption: updated.caption,
                jlptLevel: updated.jlptLevel,
                revealedAt: Date(),
                addedToDictionary: updated.addedToDictionary,
                createdAt: updated.createdAt
            )
        }
        // Refresh the missed list so the row disappears from "missed".
        missed = await service.missedTerms(limit: 14)
    }

    /// Adds the term to the user's personal dictionary and remembers the
    /// link on the daily term row.
    public func addToDictionary(_ term: DailyTermDTO) async {
        guard !term.addedToDictionary else { return }
        _ = await vocabularyRepository.addEntry(
            word: term.word,
            reading: term.reading,
            meaning: term.meaning,
            jlptLevel: term.jlptLevel
        )
        await service.markAddedToDictionary(termId: term.id)

        if term.id == today?.id, let current = today {
            today = DailyTermDTO(
                id: current.id,
                date: current.date,
                word: current.word,
                reading: current.reading,
                pronunciation: current.pronunciation,
                meaning: current.meaning,
                caption: current.caption,
                jlptLevel: current.jlptLevel,
                revealedAt: current.revealedAt,
                addedToDictionary: true,
                createdAt: current.createdAt
            )
            addedToDictionaryThisSession = true
        }
        Logger.dailyTerm.info("Daily term added to dictionary: \(term.word, privacy: .public)")
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
