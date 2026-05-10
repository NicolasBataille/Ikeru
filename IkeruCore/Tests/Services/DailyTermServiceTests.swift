import Testing
import Foundation
import SwiftData
@testable import IkeruCore

@Suite("DailyTermService")
struct DailyTermServiceTests {

    // MARK: - Helpers

    /// Builds a fresh, in-memory ModelContainer for each test.
    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([DailyTerm.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }

    private func makeService(catalog: [DailyTermCandidate] = DailyTermCatalog.all) throws -> (DailyTermService, DailyTermRepository) {
        let container = try makeContainer()
        let repo = DailyTermRepository(modelContainer: container)
        let service = DailyTermService(repository: repo, catalog: catalog)
        return (service, repo)
    }

    private func date(year: Int, month: Int, day: Int) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = 9
        return Calendar.current.date(from: components)!
    }

    // MARK: - Determinism

    @Test("Picks the same candidate for the same day twice")
    func deterministic() throws {
        let (service, _) = try makeService()
        let day = date(year: 2026, month: 5, day: 10)
        let a = service.pickCandidate(for: day, excluding: [])
        let b = service.pickCandidate(for: day, excluding: [])
        #expect(a == b)
    }

    @Test("Returns a non-empty word for any catalog entry it picks")
    func picksReturnsValidEntry() throws {
        let (service, _) = try makeService()
        let day = date(year: 2026, month: 5, day: 11) // Monday
        let pick = service.pickCandidate(for: day, excluding: [])
        #expect(!pick.word.isEmpty)
        #expect(!pick.reading.isEmpty)
        #expect(!pick.flavour.isEmpty)
    }

    // MARK: - Exclusion

    @Test("Skips words already in the user dictionary")
    func excludesDictionaryWord() throws {
        let target = DailyTermCandidate(
            word: "重複ワード",
            reading: "ちょうふくわーど",
            pronunciation: "duplicate-word",
            meaning: "duplicate word",
            flavour: "should never appear if filtered",
            tags: []
        )
        let other = DailyTermCandidate(
            word: "別ワード",
            reading: "べつわーど",
            pronunciation: "other-word",
            meaning: "other word",
            flavour: "the only available pick",
            tags: []
        )
        let (service, _) = try makeService(catalog: [target, other])
        let day = date(year: 2026, month: 5, day: 10)
        let pick = service.pickCandidate(for: day, excluding: [target.word])
        #expect(pick.word == other.word)
    }

    @Test("Falls back to full catalog when every word has been used")
    func fallsBackWhenExhausted() throws {
        let only = DailyTermCandidate(
            word: "唯一",
            reading: "ゆいいつ",
            pronunciation: "yu-i-i-tsu",
            meaning: "the only one",
            flavour: "...",
            tags: []
        )
        let (service, _) = try makeService(catalog: [only])
        let day = date(year: 2026, month: 5, day: 10)
        let pick = service.pickCandidate(for: day, excluding: [only.word])
        // With every word excluded, the service must still return *something*
        // rather than crash — falls back to the full catalog.
        #expect(pick.word == only.word)
    }

    // MARK: - Persistence

    @Test("termForDay persists a row and returns the same row on repeat calls")
    func persistsTermForDay() async throws {
        let (service, repo) = try makeService()
        let day = date(year: 2026, month: 5, day: 10)
        let first = await service.termForDay(day)
        let second = await service.termForDay(day)
        #expect(first.id == second.id)

        let stored = await repo.term(on: day)
        #expect(stored?.word == first.word)
    }

    @Test("upsertTerm via the service avoids reusing words across days")
    func avoidsReusingWords() async throws {
        let (service, repo) = try makeService()
        let day1 = date(year: 2026, month: 5, day: 10)
        let day2 = date(year: 2026, month: 5, day: 11)
        let first = await service.termForDay(day1)
        let second = await service.termForDay(day2)
        #expect(first.word != second.word)

        let used = await repo.usedWords()
        #expect(used.contains(first.word))
        #expect(used.contains(second.word))
    }

    // MARK: - Reveal & dictionary state

    @Test("markRevealed sets revealedAt only the first time")
    func markRevealedOnce() async throws {
        let (service, _) = try makeService()
        let day = date(year: 2026, month: 5, day: 10)
        let term = await service.termForDay(day)
        #expect(term.revealedAt == nil)

        await service.markRevealed(termId: term.id)
        let revealed = await service.previousDayTerm(before: date(year: 2026, month: 5, day: 11))
        #expect(revealed?.revealedAt != nil)

        let firstRevealedAt = revealed?.revealedAt
        await service.markRevealed(termId: term.id)
        let again = await service.previousDayTerm(before: date(year: 2026, month: 5, day: 11))
        #expect(again?.revealedAt == firstRevealedAt)
    }

    @Test("missedTerms returns only terms with no revealedAt")
    func missedTerms() async throws {
        let (service, _) = try makeService()
        let day1 = date(year: 2026, month: 5, day: 8)
        let day2 = date(year: 2026, month: 5, day: 9)
        let day3 = date(year: 2026, month: 5, day: 10)

        let t1 = await service.termForDay(day1)
        _ = await service.termForDay(day2) // missed
        _ = await service.termForDay(day3) // today, also unrevealed

        await service.markRevealed(termId: t1.id)

        let missed = await service.missedTerms(before: date(year: 2026, month: 5, day: 11), limit: 30)
        // Both day2 and day3 are unrevealed and strictly before May 11.
        #expect(missed.count == 2)
        #expect(missed.allSatisfy { $0.revealedAt == nil })
    }

    @Test("recentTerms returns terms in reverse-chronological order")
    func recentTermsOrder() async throws {
        let (service, _) = try makeService()
        let day1 = date(year: 2026, month: 5, day: 8)
        let day2 = date(year: 2026, month: 5, day: 9)
        let day3 = date(year: 2026, month: 5, day: 10)
        _ = await service.termForDay(day1)
        _ = await service.termForDay(day2)
        _ = await service.termForDay(day3)

        let recent = await service.recentTerms(before: date(year: 2026, month: 5, day: 11), limit: 10)
        let normalised = Calendar.current.startOfDay(for: day3)
        #expect(recent.first?.date == normalised)
    }

    // MARK: - Caption composition

    @Test("Caption includes the candidate flavour text")
    func captionIncludesFlavour() throws {
        let candidate = DailyTermCandidate(
            word: "テスト",
            reading: "てすと",
            pronunciation: "te-su-to",
            meaning: "test",
            flavour: "a unique flavour string",
            tags: []
        )
        let (service, _) = try makeService(catalog: [candidate])
        let caption = service.composeCaption(for: candidate, on: date(year: 2026, month: 5, day: 10))
        #expect(caption.contains("a unique flavour string"))
    }
}
