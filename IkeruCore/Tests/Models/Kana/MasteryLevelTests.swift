import Testing
import Foundation
@testable import IkeruCore

@Suite("MasteryLevel")
struct MasteryLevelTests {

    @Test("reps == 0 always yields .new regardless of other fields")
    func newWhenNoReps() {
        let s = FSRSState(difficulty: 5, stability: 100, reps: 0, lapses: 3, lastReview: Date())
        #expect(MasteryLevel.from(fsrsState: s) == .new)
    }

    @Test("stability < 1.0 → .learning")
    func learningWhenLowStability() {
        let s = FSRSState(difficulty: 5, stability: 0.5, reps: 1, lapses: 0, lastReview: nil)
        #expect(MasteryLevel.from(fsrsState: s) == .learning)
    }

    @Test("stability == 1.0 exactly → .familiar (boundary)")
    func familiarAtLowerBoundary() {
        let s = FSRSState(difficulty: 5, stability: 1.0, reps: 1, lapses: 0, lastReview: nil)
        #expect(MasteryLevel.from(fsrsState: s) == .familiar)
    }

    @Test("stability == 7.0 exactly → .mastered (boundary)")
    func masteredAtLowerBoundary() {
        let s = FSRSState(difficulty: 5, stability: 7.0, reps: 5, lapses: 0, lastReview: nil)
        #expect(MasteryLevel.from(fsrsState: s) == .mastered)
    }

    @Test("stability == 60.0 exactly → .anchored (boundary)")
    func anchoredAtBoundary() {
        let s = FSRSState(difficulty: 5, stability: 60.0, reps: 10, lapses: 0, lastReview: nil)
        #expect(MasteryLevel.from(fsrsState: s) == .anchored)
    }

    @Test("Recent lapse within 2 days demotes to .learning even with high stability")
    func recentLapseDemotes() {
        let now = Date()
        let recent = now.addingTimeInterval(-86_400) // 1 day ago
        let s = FSRSState(difficulty: 5, stability: 30.0, reps: 5, lapses: 1, lastReview: recent)
        #expect(MasteryLevel.from(fsrsState: s, now: now) == .learning)
    }

    @Test("Lapse older than 2 days does NOT demote")
    func oldLapseDoesNotDemote() {
        let now = Date()
        let old = now.addingTimeInterval(-3 * 86_400) // 3 days ago
        let s = FSRSState(difficulty: 5, stability: 30.0, reps: 5, lapses: 1, lastReview: old)
        #expect(MasteryLevel.from(fsrsState: s, now: now) == .mastered)
    }

    @Test("emoji is non-empty for every case", arguments: MasteryLevel.allCases)
    func emojiNonEmpty(level: MasteryLevel) {
        #expect(!level.emoji.isEmpty)
    }

    @Test("label is non-empty for every case", arguments: MasteryLevel.allCases)
    func labelNonEmpty(level: MasteryLevel) {
        #expect(!level.label.isEmpty)
    }
}
