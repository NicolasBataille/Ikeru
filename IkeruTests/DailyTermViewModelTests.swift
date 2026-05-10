import Testing
import Foundation
import SwiftData
@testable import Ikeru
@testable import IkeruCore

@Suite("DailyTermViewModel")
@MainActor
struct DailyTermViewModelTests {

    // MARK: - Helpers

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([
            DailyTerm.self,
            VocabularyEntry.self,
            VocabularyEncounter.self
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }

    /// Wires UserDefaults via a per-test suite name so tests don't bleed.
    /// The view model reads `UserDefaults.standard`, so we override the
    /// standard suite for the duration of the test.
    private func withFeatureEnabled<T>(_ enabled: Bool = true, _ body: () async throws -> T) async rethrows -> T {
        let prior = UserDefaults.standard.object(forKey: DailyTermSettings.enabledKey)
        UserDefaults.standard.set(enabled, forKey: DailyTermSettings.enabledKey)
        defer {
            if let prior {
                UserDefaults.standard.set(prior, forKey: DailyTermSettings.enabledKey)
            } else {
                UserDefaults.standard.removeObject(forKey: DailyTermSettings.enabledKey)
            }
        }
        return try await body()
    }

    private func date(year: Int, month: Int, day: Int, hour: Int = 9) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        return Calendar.current.date(from: components)!
    }

    // MARK: - Loading

    @Test("load() populates today and recent when feature enabled")
    func loadPopulatesWhenEnabled() async throws {
        try await withFeatureEnabled {
            let container = try makeContainer()
            let vm = DailyTermViewModel(modelContainer: container)
            let now = date(year: 2026, month: 5, day: 10)
            await vm.load(now: now)
            #expect(vm.hasLoaded)
            #expect(vm.today != nil)
            #expect(vm.todayNeedsReveal == true)
        }
    }

    @Test("load() short-circuits and clears state when feature disabled")
    func loadDisabled() async throws {
        try await withFeatureEnabled(false) {
            let container = try makeContainer()
            let vm = DailyTermViewModel(modelContainer: container)
            await vm.load(now: date(year: 2026, month: 5, day: 10))
            #expect(vm.today == nil)
            #expect(vm.recent.isEmpty)
            #expect(vm.hasLoaded)
        }
    }

    @Test("load() excludes words already in the user dictionary")
    func loadExcludesDictionaryWords() async throws {
        try await withFeatureEnabled {
            let container = try makeContainer()
            // Pre-add a daily-catalog word to the dictionary.
            let preExisting = DailyTermCatalog.all.first!
            let vocabRepo = VocabularyRepository(modelContainer: container)
            _ = await vocabRepo.addEntry(
                word: preExisting.word,
                reading: preExisting.reading,
                meaning: preExisting.meaning
            )

            let vm = DailyTermViewModel(modelContainer: container)
            await vm.load(now: date(year: 2026, month: 5, day: 10))
            #expect(vm.today != nil)
            #expect(vm.today?.word != preExisting.word)
        }
    }

    // MARK: - Mutations

    @Test("markRevealed updates today.revealedAt and removes the row from missed")
    func markRevealedFlow() async throws {
        try await withFeatureEnabled {
            let container = try makeContainer()
            let vm = DailyTermViewModel(modelContainer: container)
            let now = date(year: 2026, month: 5, day: 10)
            await vm.load(now: now)
            let term = vm.today!

            let updated = await vm.markRevealed(term, now: now)
            #expect(updated?.revealedAt != nil)
            #expect(vm.today?.revealedAt != nil)
            #expect(vm.todayNeedsReveal == false)
            #expect(vm.missed.contains { $0.id == term.id } == false)
        }
    }

    @Test("markRevealed is a no-op when already revealed")
    func markRevealedIdempotent() async throws {
        try await withFeatureEnabled {
            let container = try makeContainer()
            let vm = DailyTermViewModel(modelContainer: container)
            await vm.load(now: date(year: 2026, month: 5, day: 10))
            let term = vm.today!
            _ = await vm.markRevealed(term)
            let alreadyRevealed = vm.today!
            let secondCall = await vm.markRevealed(alreadyRevealed)
            #expect(secondCall == nil)
        }
    }

    @Test("addToDictionary writes a vocab row and flips addedToDictionary")
    func addToDictionaryWrites() async throws {
        try await withFeatureEnabled {
            let container = try makeContainer()
            let vm = DailyTermViewModel(modelContainer: container)
            await vm.load(now: date(year: 2026, month: 5, day: 10))
            let term = vm.today!

            let updated = await vm.addToDictionary(term)
            #expect(updated?.addedToDictionary == true)
            #expect(vm.today?.addedToDictionary == true)

            let vocabRepo = VocabularyRepository(modelContainer: container)
            #expect(await vocabRepo.hasEntry(forWord: term.word))
        }
    }

    @Test("addToDictionary is a no-op when already added")
    func addToDictionaryIdempotent() async throws {
        try await withFeatureEnabled {
            let container = try makeContainer()
            let vm = DailyTermViewModel(modelContainer: container)
            await vm.load(now: date(year: 2026, month: 5, day: 10))
            let term = vm.today!
            _ = await vm.addToDictionary(term)
            let alreadyAdded = vm.today!
            let second = await vm.addToDictionary(alreadyAdded)
            #expect(second == nil)
        }
    }

    // MARK: - Day rollover

    @Test("reloadIfDayChanged is a no-op when the day hasn't changed")
    func reloadIfDayChangedSameDay() async throws {
        try await withFeatureEnabled {
            let container = try makeContainer()
            let vm = DailyTermViewModel(modelContainer: container)
            let morning = date(year: 2026, month: 5, day: 10, hour: 6)
            await vm.load(now: morning)
            let firstId = vm.today?.id

            let evening = date(year: 2026, month: 5, day: 10, hour: 22)
            await vm.reloadIfDayChanged(now: evening)
            #expect(vm.today?.id == firstId)
        }
    }

    @Test("reloadIfDayChanged refreshes when the calendar day rolls over")
    func reloadIfDayChangedNewDay() async throws {
        try await withFeatureEnabled {
            let container = try makeContainer()
            let vm = DailyTermViewModel(modelContainer: container)
            await vm.load(now: date(year: 2026, month: 5, day: 10))
            let firstWord = vm.today?.word

            await vm.reloadIfDayChanged(now: date(year: 2026, month: 5, day: 11))
            // The next day must produce a different term — words don't repeat.
            #expect(vm.today?.word != nil)
            #expect(vm.today?.word != firstWord)
        }
    }

    // MARK: - DailyTermSettings UserDefaults round-trip

    @Test("DailyTermSettings hour and minute round-trip via @AppStorage-style writes")
    func settingsRoundTrip() throws {
        let priorHour = UserDefaults.standard.object(forKey: DailyTermSettings.hourKey)
        let priorMinute = UserDefaults.standard.object(forKey: DailyTermSettings.minuteKey)
        defer {
            if let priorHour {
                UserDefaults.standard.set(priorHour, forKey: DailyTermSettings.hourKey)
            } else {
                UserDefaults.standard.removeObject(forKey: DailyTermSettings.hourKey)
            }
            if let priorMinute {
                UserDefaults.standard.set(priorMinute, forKey: DailyTermSettings.minuteKey)
            } else {
                UserDefaults.standard.removeObject(forKey: DailyTermSettings.minuteKey)
            }
        }

        // Write via the same set(_:forKey:) that @AppStorage emits.
        UserDefaults.standard.set(8, forKey: DailyTermSettings.hourKey)
        UserDefaults.standard.set(30, forKey: DailyTermSettings.minuteKey)

        // Read via the same `as? Int` cast IkeruApp.swift uses.
        let hour = UserDefaults.standard.object(forKey: DailyTermSettings.hourKey) as? Int
        let minute = UserDefaults.standard.object(forKey: DailyTermSettings.minuteKey) as? Int
        #expect(hour == 8)
        #expect(minute == 30)
    }
}
