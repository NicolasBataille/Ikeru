import Testing
import Foundation
@testable import IkeruCore

@Suite("WatchSyncPayload")
struct WatchSyncPayloadTests {

    @Test("Dictionary round-trip preserves all fields")
    func dictionaryRoundTrip() {
        let payload = WatchSyncPayload(
            xp: 500,
            level: 5,
            totalReviews: 100,
            dueCardCount: 12,
            timestamp: Date(timeIntervalSince1970: 1_000_000),
            source: .iPhone
        )

        let dict = payload.toDictionary()
        let decoded = WatchSyncPayload.fromDictionary(dict)

        #expect(decoded != nil)
        #expect(decoded?.xp == 500)
        #expect(decoded?.level == 5)
        #expect(decoded?.totalReviews == 100)
        #expect(decoded?.dueCardCount == 12)
        #expect(decoded?.source == .iPhone)
    }

    @Test("Watch session result round-trip")
    func sessionResultRoundTrip() {
        let result = WatchSessionResult(
            correctCount: 8,
            totalQuestions: 10,
            drillType: .kanaQuiz,
            xpEarned: 40
        )

        let dict = result.toDictionary()
        let decoded = WatchSessionResult.fromDictionary(dict)

        #expect(decoded != nil)
        #expect(decoded?.correctCount == 8)
        #expect(decoded?.totalQuestions == 10)
        #expect(decoded?.drillType == .kanaQuiz)
        #expect(decoded?.xpEarned == 40)
    }
}

@Suite("SyncConflictResolver")
struct SyncConflictResolverTests {

    @Test("More recent timestamp wins")
    func recentTimestampWins() {
        let earlier = WatchSyncPayload(
            xp: 100, level: 2, totalReviews: 20, dueCardCount: 5,
            timestamp: Date(timeIntervalSince1970: 1000),
            source: .iPhone
        )
        let later = WatchSyncPayload(
            xp: 200, level: 3, totalReviews: 30, dueCardCount: 3,
            timestamp: Date(timeIntervalSince1970: 2000),
            source: .watch
        )

        let winner = SyncConflictResolver.resolve(local: earlier, remote: later)
        #expect(winner.xp == 200)
        #expect(winner.source == .watch)
    }

    @Test("Local wins when timestamps are equal")
    func localWinsOnTie() {
        let now = Date()
        let local = WatchSyncPayload(
            xp: 100, level: 2, totalReviews: 20, dueCardCount: 5,
            timestamp: now, source: .iPhone
        )
        let remote = WatchSyncPayload(
            xp: 200, level: 3, totalReviews: 30, dueCardCount: 3,
            timestamp: now, source: .watch
        )

        let winner = SyncConflictResolver.resolve(local: local, remote: remote)
        #expect(winner.source == .iPhone)
    }
}
