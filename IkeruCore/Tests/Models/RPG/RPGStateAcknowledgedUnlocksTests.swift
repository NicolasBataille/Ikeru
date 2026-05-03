import Testing
import Foundation
@testable import IkeruCore

@Suite("RPGState.acknowledgedUnlocks")
struct RPGStateAcknowledgedUnlocksTests {

    @Test("Defaults to empty set when never set")
    func defaultEmpty() {
        let s = RPGState()
        #expect(s.acknowledgedUnlocks.isEmpty)
    }

    @Test("Round-trips a set through encoding")
    func roundTrip() {
        let s = RPGState()
        s.acknowledgedUnlocks = [.kanaStudy, .vocabularyStudy, .listeningSubtitled]
        #expect(s.acknowledgedUnlocks == [.kanaStudy, .vocabularyStudy, .listeningSubtitled])
    }

    @Test("Empty assignment clears the underlying data")
    func emptyAssignment() {
        let s = RPGState()
        s.acknowledgedUnlocks = [.kanaStudy]
        #expect(s.acknowledgedUnlocks == [.kanaStudy])
        s.acknowledgedUnlocks = []
        #expect(s.acknowledgedUnlocks.isEmpty)
    }
}
