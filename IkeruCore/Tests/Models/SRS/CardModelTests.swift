import Testing
import Foundation
import SwiftData
@testable import IkeruCore

// MARK: - CardType Tests

@Suite("CardType Enum")
struct CardTypeTests {

    @Test("All card types have correct raw values")
    func rawValues() {
        #expect(CardType.kanji.rawValue == "kanji")
        #expect(CardType.vocabulary.rawValue == "vocabulary")
        #expect(CardType.grammar.rawValue == "grammar")
        #expect(CardType.listening.rawValue == "listening")
    }

    @Test("CardType initializes from raw value")
    func initFromRawValue() {
        #expect(CardType(rawValue: "kanji") == .kanji)
        #expect(CardType(rawValue: "vocabulary") == .vocabulary)
        #expect(CardType(rawValue: "grammar") == .grammar)
        #expect(CardType(rawValue: "listening") == .listening)
    }

    @Test("CardType returns nil for invalid raw value")
    func invalidRawValue() {
        #expect(CardType(rawValue: "invalid") == nil)
    }

    @Test("CardType has exactly 4 cases")
    func caseCount() {
        #expect(CardType.allCases.count == 4)
    }
}

// MARK: - Grade Tests

@Suite("Grade Enum")
struct GradeTests {

    @Test("Grade raw values are ordered 1-4")
    func rawValues() {
        #expect(Grade.again.rawValue == 1)
        #expect(Grade.hard.rawValue == 2)
        #expect(Grade.good.rawValue == 3)
        #expect(Grade.easy.rawValue == 4)
    }

    @Test("Grade initializes from raw value")
    func initFromRawValue() {
        #expect(Grade(rawValue: 1) == .again)
        #expect(Grade(rawValue: 2) == .hard)
        #expect(Grade(rawValue: 3) == .good)
        #expect(Grade(rawValue: 4) == .easy)
    }

    @Test("Grade returns nil for invalid raw value")
    func invalidRawValue() {
        #expect(Grade(rawValue: 0) == nil)
        #expect(Grade(rawValue: 5) == nil)
    }

    @Test("Grade has exactly 4 cases")
    func caseCount() {
        #expect(Grade.allCases.count == 4)
    }
}

// MARK: - FSRSState Tests

@Suite("FSRSState Struct")
struct FSRSStateTests {

    @Test("Default FSRSState has correct initial values")
    func defaultInit() {
        let state = FSRSState()
        #expect(state.difficulty == 0)
        #expect(state.stability == 0)
        #expect(state.reps == 0)
        #expect(state.lapses == 0)
        #expect(state.lastReview == nil)
    }

    @Test("FSRSState initializes with custom values")
    func customInit() {
        let reviewDate = Date()
        let state = FSRSState(
            difficulty: 5.5,
            stability: 10.0,
            reps: 3,
            lapses: 1,
            lastReview: reviewDate
        )
        #expect(state.difficulty == 5.5)
        #expect(state.stability == 10.0)
        #expect(state.reps == 3)
        #expect(state.lapses == 1)
        #expect(state.lastReview == reviewDate)
    }

    @Test("FSRSState is Codable - encode and decode roundtrip")
    func codableRoundtrip() throws {
        let reviewDate = Date(timeIntervalSinceReferenceDate: 1000)
        let original = FSRSState(
            difficulty: 5.5,
            stability: 10.0,
            reps: 3,
            lapses: 1,
            lastReview: reviewDate
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(FSRSState.self, from: data)
        #expect(decoded.difficulty == original.difficulty)
        #expect(decoded.stability == original.stability)
        #expect(decoded.reps == original.reps)
        #expect(decoded.lapses == original.lapses)
        #expect(decoded.lastReview == original.lastReview)
    }

    @Test("FSRSState Codable handles nil lastReview")
    func codableNilLastReview() throws {
        let original = FSRSState()
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(FSRSState.self, from: data)
        #expect(decoded.lastReview == nil)
    }

    @Test("FSRSState is Equatable")
    func equatable() {
        let date = Date()
        let a = FSRSState(difficulty: 5, stability: 10, reps: 3, lapses: 1, lastReview: date)
        let b = FSRSState(difficulty: 5, stability: 10, reps: 3, lapses: 1, lastReview: date)
        #expect(a == b)
    }
}

// MARK: - ProfileSettings Tests

@Suite("ProfileSettings Struct")
struct ProfileSettingsTests {

    @Test("Default ProfileSettings has correct initial values")
    func defaultInit() {
        let settings = ProfileSettings()
        #expect(settings.desiredRetention == 0.9)
        #expect(settings.dailyNewCardLimit == 20)
        #expect(settings.dailyReviewLimit == 200)
    }

    @Test("ProfileSettings is Codable - encode and decode roundtrip")
    func codableRoundtrip() throws {
        let original = ProfileSettings(
            desiredRetention: 0.85,
            dailyNewCardLimit: 10,
            dailyReviewLimit: 100
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ProfileSettings.self, from: data)
        #expect(decoded.desiredRetention == original.desiredRetention)
        #expect(decoded.dailyNewCardLimit == original.dailyNewCardLimit)
        #expect(decoded.dailyReviewLimit == original.dailyReviewLimit)
    }
}

// MARK: - Helper

private func makeTestContainer() throws -> ModelContainer {
    let schema = Schema([UserProfile.self, Card.self, ReviewLog.self])
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    return try ModelContainer(for: schema, configurations: [config])
}

// MARK: - Card Model Tests

@Suite("Card Model")
struct CardModelTests {

    @Test("Card initializes with required fields")
    func cardInit() throws {
        let container = try makeTestContainer()
        let context = ModelContext(container)
        let card = Card(
            front: "日",
            back: "day/sun",
            type: .kanji
        )
        context.insert(card)
        #expect(card.front == "日")
        #expect(card.back == "day/sun")
        #expect(card.type == .kanji)
        #expect(card.typeRawValue == "kanji")
        #expect(card.fsrsState == FSRSState())
        #expect(card.easeFactor == 2.5)
        #expect(card.interval == 0)
        #expect(card.lapseCount == 0)
        #expect(card.leechFlag == false)
    }

    @Test("Card type enum stored correctly for each type", arguments: CardType.allCases)
    func cardTypeStorage(type: CardType) throws {
        let container = try makeTestContainer()
        let context = ModelContext(container)
        let card = Card(front: "test", back: "test", type: type)
        context.insert(card)
        #expect(card.type == type)
        #expect(card.typeRawValue == type.rawValue)
    }
}

// MARK: - ReviewLog Model Tests

@Suite("ReviewLog Model")
struct ReviewLogTests {

    @Test("ReviewLog initializes with required fields")
    func reviewLogInit() throws {
        let container = try makeTestContainer()
        let context = ModelContext(container)
        let card = Card(front: "日", back: "day", type: .kanji)
        context.insert(card)
        let log = ReviewLog(
            card: card,
            grade: .good,
            responseTimeMs: 1500
        )
        context.insert(log)
        #expect(log.grade == .good)
        #expect(log.gradeRawValue == 3)
        #expect(log.responseTimeMs == 1500)
        #expect(log.card === card)
    }
}

// MARK: - UserProfile Model Tests

@Suite("UserProfile Model")
struct UserProfileTests {

    @Test("UserProfile initializes with display name")
    func userProfileInit() throws {
        let container = try makeTestContainer()
        let context = ModelContext(container)
        let profile = UserProfile(displayName: "Nico")
        context.insert(profile)
        #expect(profile.displayName == "Nico")
        #expect(profile.settings == ProfileSettings())
        #expect(profile.cards != nil)
    }
}
