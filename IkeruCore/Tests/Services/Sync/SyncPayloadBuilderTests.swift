import Testing
import Foundation
@testable import IkeruCore

@Suite("SyncPayloadBuilder")
struct SyncPayloadBuilderTests {

    @Test("Card row carries id, profile_id, updated_at, deleted_at, and a payload object")
    func cardRow() throws {
        let profile = UserProfile(displayName: "Test")
        let card = Card(front: "犬", back: "dog", type: .vocabulary)
        card.profile = profile

        let row = try SyncPayloadBuilder.row(for: card)

        #expect(row["id"] == .uuid(card.id))
        #expect(row["profile_id"] == .uuid(profile.id))
        #expect(row["updated_at"] == .date(card.updatedAt))
        #expect(row["deleted_at"] == .null)
        guard case .object(let payload) = row["payload"] else {
            Issue.record("Expected payload object")
            return
        }
        #expect(payload["front"] == .string("犬"))
        #expect(payload["back"] == .string("dog"))
        #expect(payload["type"] == .string("vocabulary"))
    }

    @Test("Card row omits user_id entirely — the server default (auth.uid()) owns it")
    func cardRowOmitsUserID() throws {
        let card = Card(front: "a", back: "b", type: .kanji)
        let row = try SyncPayloadBuilder.row(for: card)
        #expect(row["user_id"] == nil)
    }

    @Test("Card with no profile pushes profile_id as null, not a fabricated value")
    func cardRowWithoutProfile() throws {
        let card = Card(front: "a", back: "b", type: .kanji)
        let row = try SyncPayloadBuilder.row(for: card)
        #expect(row["profile_id"] == .null)
    }

    @Test("VocabularyEntry row always pushes profile_id as null — no profile relationship exists on the model")
    func vocabularyEntryRowProfileIDIsAlwaysNull() throws {
        let entry = VocabularyEntry(word: "犬", reading: "いぬ", meaning: "dog")
        let row = try SyncPayloadBuilder.row(for: entry)
        #expect(row["profile_id"] == .null)
    }

    @Test("ReviewLog row flattens card_id/grade/answered_value/exercise_type/surface as columns, not just payload")
    func reviewLogRowFlattensColumns() throws {
        let card = Card(front: "a", back: "b", type: .kanji)
        let log = ReviewLog(
            card: card,
            grade: .good,
            responseTimeMs: 1234,
            answeredValue: "ツ",
            exerciseType: "kana.quiz",
            surface: "iphone.drill"
        )

        let row = try SyncPayloadBuilder.row(for: log)

        #expect(row["card_id"] == .uuid(card.id))
        #expect(row["grade"] == .number(Double(Grade.good.rawValue)))
        #expect(row["answered_value"] == .string("ツ"))
        #expect(row["exercise_type"] == .string("kana.quiz"))
        #expect(row["surface"] == .string("iphone.drill"))
        #expect(row["occurred_at"] == .date(log.timestamp))
    }

    @Test("ExerciseOutcomeLog row uses the model's scalar profileID directly")
    func exerciseOutcomeLogRowUsesScalarProfileID() throws {
        let profileID = UUID()
        let log = ExerciseOutcomeLog(skill: .listening, accuracy: 0.8, profileID: profileID)
        let row = try SyncPayloadBuilder.row(for: log)
        #expect(row["profile_id"] == .uuid(profileID))
        #expect(row["occurred_at"] == .date(log.timestamp))
    }

    @Test("VocabularyEncounter row uses entry_id, not profile_id")
    func vocabularyEncounterRowUsesEntryID() throws {
        let entry = VocabularyEntry(word: "犬", reading: "いぬ", meaning: "dog")
        let encounter = VocabularyEncounter(source: .sakuraChat, contextSnippet: "犬が好き", entry: entry)
        let row = try SyncPayloadBuilder.row(for: encounter)
        #expect(row["entry_id"] == .uuid(entry.id))
        #expect(row["profile_id"] == nil)
    }

    @Test("VocabularyEncounter row never carries the context snippet off the device")
    func vocabularyEncounterRowOmitsContextSnippet() throws {
        // The snippet is the sentence the word was met in. When the source is
        // Sakura that sentence is conversation content — text the learner typed
        // or the model wrote back to them. Pushing it here would route chat
        // content to the server through the vocabulary table, side-stepping the
        // separate opt-in companion_chat_messages is held back for.
        //
        // Asserting on the encoded payload rather than on the Swift struct: the
        // struct can gain a field back without anyone noticing, and it is the
        // encoded bytes that actually leave.
        let entry = VocabularyEntry(word: "犬", reading: "いぬ", meaning: "dog")
        let snippet = "昨日、犬と散歩しました"
        let encounter = VocabularyEncounter(source: .sakuraChat, contextSnippet: snippet, entry: entry)

        let row = try SyncPayloadBuilder.row(for: encounter)
        let encoded = try JSONEncoder().encode(row["payload"])
        let json = try #require(String(bytes: encoded, encoding: .utf8))

        #expect(!json.contains(snippet))
        #expect(!json.lowercased().contains("snippet"))
        // The source itself is the pedagogical signal, and it does travel.
        #expect(json.contains(encounter.sourceRawValue))
    }

    @Test("RPGState row carries monotone counters in payload and profile_id from the relationship")
    func rpgStateRow() throws {
        let profile = UserProfile(displayName: "Test")
        let state = RPGState(xp: 100, level: 3, totalReviewsCompleted: 50)
        state.profile = profile

        let row = try SyncPayloadBuilder.row(for: state)
        #expect(row["profile_id"] == .uuid(profile.id))
        guard case .object(let payload) = row["payload"] else {
            Issue.record("Expected payload object")
            return
        }
        #expect(payload["xp"] == .number(100))
        #expect(payload["level"] == .number(3))
    }

    @Test("UserProfile row has no profile_id column — it IS the profile")
    func userProfileRowHasNoProfileIDColumn() throws {
        let profile = UserProfile(displayName: "Test")
        let row = try SyncPayloadBuilder.row(for: profile)
        #expect(row["profile_id"] == nil)
        #expect(row["id"] == .uuid(profile.id))
    }

    @Test("deleted_at reflects a tombstoned row")
    func deletedAtReflectsTombstone() throws {
        let card = Card(front: "a", back: "b", type: .kanji)
        let tombstoneDate = Date(timeIntervalSince1970: 1_700_000_000)
        card.deletedAt = tombstoneDate
        let row = try SyncPayloadBuilder.row(for: card)
        #expect(row["deleted_at"] == .date(tombstoneDate))
    }
}
