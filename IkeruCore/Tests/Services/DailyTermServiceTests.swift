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

    /// Builds a date with a specific *hour* so we can test that two
    /// different timestamps on the same calendar day are treated equally.
    private func date(year: Int, month: Int, day: Int, hour: Int = 9) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        return Calendar.current.date(from: components)!
    }

    /// A small synthetic catalog with disjoint tags so the scoring test can
    /// assert "the Monday-tagged candidate wins on a Monday".
    private let monCandidate = DailyTermCandidate(
        word: "月示",
        reading: "つきしめし",
        pronunciation: "tsu-ki-shi-me-shi",
        meaning: "Monday marker",
        flavour: "should win on Mondays",
        tags: ["monday"]
    )
    private let friCandidate = DailyTermCandidate(
        word: "金示",
        reading: "きんしめし",
        pronunciation: "ki-n-shi-me-shi",
        meaning: "Friday marker",
        flavour: "should win on Fridays",
        tags: ["friday"]
    )
    private let neutralCandidate = DailyTermCandidate(
        word: "中立",
        reading: "ちゅうりつ",
        pronunciation: "chu-u-ri-tsu",
        meaning: "neutral",
        flavour: "no day tag",
        tags: []
    )

    // MARK: - Determinism

    @Test("Picks the same candidate for the same day twice")
    func deterministic() throws {
        let (service, _) = try makeService()
        let day = date(year: 2026, month: 5, day: 10)
        let a = service.pickCandidate(for: day, excluding: [])
        let b = service.pickCandidate(for: day, excluding: [])
        #expect(a == b)
    }

    @Test("Different times on the same day yield the same term")
    func sameDayDifferentHours() async throws {
        let (service, _) = try makeService()
        let morning = date(year: 2026, month: 5, day: 10, hour: 0)
        let evening = date(year: 2026, month: 5, day: 10, hour: 23)
        let first = await service.termForDay(morning)
        let second = await service.termForDay(evening)
        #expect(first.id == second.id)
        #expect(first.word == second.word)
    }

    @Test("Returns a non-empty word for any catalog entry it picks")
    func picksReturnsValidEntry() throws {
        let (service, _) = try makeService()
        // 2026-05-10 is a Sunday; verify the service returns a real entry.
        let day = date(year: 2026, month: 5, day: 10)
        let pick = service.pickCandidate(for: day, excluding: [])
        #expect(!pick.word.isEmpty)
        #expect(!pick.reading.isEmpty)
        #expect(!pick.flavour.isEmpty)
    }

    // MARK: - Tag-based scoring

    @Test("Monday-tagged candidate wins on a Monday over a Friday-tagged one")
    func tagScoringPrefersDayMatch() throws {
        let (service, _) = try makeService(catalog: [monCandidate, friCandidate, neutralCandidate])
        // 2026-05-11 is a Monday.
        let monday = date(year: 2026, month: 5, day: 11)
        let pick = service.pickCandidate(for: monday, excluding: [])
        #expect(pick.word == monCandidate.word)
    }

    @Test("Friday-tagged candidate wins on a Friday")
    func tagScoringFriday() throws {
        let (service, _) = try makeService(catalog: [monCandidate, friCandidate, neutralCandidate])
        // 2026-05-15 is a Friday.
        let friday = date(year: 2026, month: 5, day: 15)
        let pick = service.pickCandidate(for: friday, excluding: [])
        #expect(pick.word == friCandidate.word)
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

    @Test("Falls back to the full catalog when every word has been excluded — and rotates by date")
    func fallsBackWhenExhausted() throws {
        let candidates = (0..<6).map { i in
            DailyTermCandidate(
                word: "W\(i)",
                reading: "W\(i)",
                pronunciation: "w-\(i)",
                meaning: "word \(i)",
                flavour: "flavour \(i)",
                tags: []
            )
        }
        let allExcluded = Set(candidates.map(\.word))
        let (service, _) = try makeService(catalog: candidates)

        let pickA = service.pickCandidate(
            for: date(year: 2026, month: 5, day: 10),
            excluding: allExcluded
        )
        let pickB = service.pickCandidate(
            for: date(year: 2026, month: 5, day: 17),
            excluding: allExcluded
        )

        // Both picks must come from the catalog (real entries, not crash).
        #expect(candidates.contains(pickA))
        #expect(candidates.contains(pickB))
        // And the date seed must produce some variation rather than locking
        // onto a single word — over a one-week shift the rotation should
        // change.
        #expect(pickA != pickB)
    }

    // MARK: - Persistence

    @Test("termForDay persists a row and returns the same row on repeat calls")
    func persistsTermForDay() async throws {
        let (service, repo) = try makeService()
        let day = date(year: 2026, month: 5, day: 10)
        let first = await service.termForDay(day)
        let second = await service.termForDay(day)
        #expect(first.id == second.id)

        // Service normalises to startOfDay before persisting; direct repo
        // lookups must match the same key.
        let stored = await repo.term(on: Calendar.current.startOfDay(for: day))
        #expect(stored?.word == first.word)
    }

    @Test("upsertTerm with a row already present returns the existing row, ignoring new content")
    func upsertHonoursExistingRow() async throws {
        let (_, repo) = try makeService()
        let day = date(year: 2026, month: 5, day: 10)
        let first = await repo.upsertTerm(
            on: day,
            word: "First",
            reading: "first",
            pronunciation: "f-i",
            meaning: "first meaning",
            caption: "first caption",
            jlptLevel: nil
        )
        let second = await repo.upsertTerm(
            on: day,
            word: "Replacement",
            reading: "replacement",
            pronunciation: "r-i",
            meaning: "should not overwrite",
            caption: "should not overwrite",
            jlptLevel: nil
        )
        #expect(first.id == second.id)
        #expect(second.word == "First")
    }

    @Test("termForDay avoids reusing words across days")
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
        // Sleep a few ms — if a buggy re-stamp re-writes the timestamp,
        // it should be detectable.
        try await Task.sleep(nanoseconds: 5_000_000)
        await service.markRevealed(termId: term.id)
        let again = await service.previousDayTerm(before: date(year: 2026, month: 5, day: 11))
        #expect(again?.revealedAt == firstRevealedAt)
    }

    @Test("markAddedToDictionary flips the flag")
    func markAddedToDictionary() async throws {
        let (service, repo) = try makeService()
        let day = date(year: 2026, month: 5, day: 10)
        let term = await service.termForDay(day)
        #expect(term.addedToDictionary == false)
        await service.markAddedToDictionary(termId: term.id)
        let after = await repo.term(on: Calendar.current.startOfDay(for: day))
        #expect(after?.addedToDictionary == true)
    }

    @Test("missedTerms returns only terms with no revealedAt")
    func missedTerms() async throws {
        let (service, _) = try makeService()
        let day1 = date(year: 2026, month: 5, day: 8)
        let day2 = date(year: 2026, month: 5, day: 9)
        let day3 = date(year: 2026, month: 5, day: 10)

        let t1 = await service.termForDay(day1)
        _ = await service.termForDay(day2) // missed
        _ = await service.termForDay(day3) // also unrevealed

        await service.markRevealed(termId: t1.id)

        let missed = await service.missedTerms(before: date(year: 2026, month: 5, day: 11), limit: 30)
        #expect(missed.count == 2)
        #expect(missed.allSatisfy { $0.revealedAt == nil })
    }

    @Test("recentTerms returns past terms in reverse-chronological order, capped at limit")
    func recentTermsOrder() async throws {
        let (service, _) = try makeService()
        let days = (1...5).map { date(year: 2026, month: 5, day: $0) }
        for day in days {
            _ = await service.termForDay(day)
        }
        let recent = await service.recentTerms(before: date(year: 2026, month: 5, day: 11), limit: 3)
        #expect(recent.count == 3)
        let dates = recent.map(\.date)
        // Strictly descending.
        for i in 0..<(dates.count - 1) {
            #expect(dates[i] > dates[i + 1])
        }
    }

    @Test("previousDayTerm returns the most recent past term regardless of how old")
    func previousDayBoundary() async throws {
        let (service, _) = try makeService()
        let oldDay = date(year: 2026, month: 4, day: 1)
        let recentDay = date(year: 2026, month: 5, day: 9)
        _ = await service.termForDay(oldDay)
        let recent = await service.termForDay(recentDay)

        let prev = await service.previousDayTerm(before: date(year: 2026, month: 5, day: 10))
        #expect(prev?.id == recent.id)
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

    @Test("Caption mentions the day phrase (weekday + season)")
    func captionMentionsDayPhrase() throws {
        let candidate = DailyTermCandidate(
            word: "テスト",
            reading: "てすと",
            pronunciation: "te-su-to",
            meaning: "test",
            flavour: "an arbitrary flavour",
            tags: []
        )
        let (service, _) = try makeService(catalog: [candidate])
        // 2026-05-11 is Monday in spring.
        let caption = service.composeCaption(for: candidate, on: date(year: 2026, month: 5, day: 11))
        #expect(caption.contains("Monday") || caption.contains("spring"))
    }

    // MARK: - Tag generation

    @Test("Tags include weekend marker for Saturday")
    func weekendTagSaturday() {
        // 2026-05-09 is a Saturday.
        let saturday = date(year: 2026, month: 5, day: 9)
        let tags = DailyTermService.tags(for: saturday, calendar: .current)
        #expect(tags.contains("weekend"))
        #expect(tags.contains("saturday"))
        #expect(tags.contains("spring"))
    }
}
